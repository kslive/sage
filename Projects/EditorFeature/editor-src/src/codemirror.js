// Sage editor — CodeMirror 6 в source-режиме с Live Preview (ENTRY-точка).
// Правит СЫРОЙ markdown напрямую → форматирование чужих .md никогда не ломается
// (нет round-trip через AST, как было в Milkdown). Undo встроенный и per-документ.
// Мост Swift↔webview сохранён 1-в-1 (sageSetDoc/SetMode/SetTheme/... + сообщения doc/selection/...).
// Вся тестируемая логика (виджеты, builder'ы декораций, чистые функции, регэкспы) — в core.js.
import { EditorState, Compartment } from "@codemirror/state";
import { EditorView, keymap, drawSelection, dropCursor } from "@codemirror/view";
import { history, historyKeymap, defaultKeymap, indentWithTab } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { forceParsing, syntaxTree } from "@codemirror/language";
import {
  markField, setMark, clearMark, focusField, setFocus, blockField, livePreviewPlugin, baseTheme,
  isLivePreview, setLivePreview, setBaseFolder, bodyStartOffset, decideToggle, linkMarkdown, SLASH_RE,
  shouldCollapseClick, docSendDelay, autoPeriodBefore,
} from "./core.js";

function send(msg) { try { window.webkit.messageHandlers.sage.postMessage(msg); } catch (e) {} }

const rootEl = document.getElementById("editor");
let view = null;
let currentEpoch = 0;
let suppress = false;       // не слать doc во время программной установки документа
let docTimer = null, selTimer = null;
let docFirstPendingAt = 0;  // время первого несохранённого ввода (для maxWait)

const previewCompartment = new Compartment();

// ── Сохранение (только реальные правки пользователя; текст = сырой, без нормализации) ──
function scheduleDoc() {
  if (suppress) return;
  const now = Date.now();
  if (!docFirstPendingAt) docFirstPendingAt = now;
  if (docTimer) clearTimeout(docTimer);
  const epoch = currentEpoch;
  docTimer = setTimeout(() => {
    docTimer = null; docFirstPendingAt = 0;
    if (!view) return;
    send({ type: "doc", text: view.state.doc.toString(), epoch });
  }, docSendDelay(now, docFirstPendingAt));
}
function emitSelection() {
  if (!view) return;
  const { from, to } = view.state.selection.main;
  send({ type: "selection", text: from === to ? "" : view.state.doc.sliceString(from, to) });
}

const updateListener = EditorView.updateListener.of((u) => {
  if (u.docChanged) scheduleDoc();
  if (u.selectionSet) {
    if (selTimer) clearTimeout(selTimer);
    selTimer = setTimeout(() => { emitSelection(); updateToolbar(); checkSlash(); }, 60);
  }
});

// ── Форматирование выделения (тоггл как в Notion) ─────────────────────────────
function wrapSelection(before, after) {
  if (!view) return;
  const sel = view.state.selection.main;
  const doc = view.state.doc;
  const text = doc.sliceString(sel.from, sel.to);
  const pre = doc.sliceString(Math.max(0, sel.from - before.length), sel.from);
  const post = doc.sliceString(sel.to, Math.min(doc.length, sel.to + after.length));
  const decision = decideToggle(text, pre, post, before, after);
  // 1) маркеры внутри самого выделения → снять
  if (decision === "inside") {
    const inner = text.slice(before.length, text.length - after.length);
    view.dispatch({ changes: { from: sel.from, to: sel.to, insert: inner },
      selection: { anchor: sel.from, head: sel.from + inner.length }, userEvent: "input" });
    view.focus(); return;
  }
  // 2) маркеры ВОКРУГ выделения → снять
  if (decision === "around") {
    view.dispatch({ changes: [
      { from: sel.from - before.length, to: sel.from, insert: "" },
      { from: sel.to, to: sel.to + after.length, insert: "" },
    ], selection: { anchor: sel.from - before.length, head: sel.to - before.length }, userEvent: "input" });
    view.focus(); return;
  }
  // 3) иначе обернуть
  view.dispatch({
    changes: { from: sel.from, to: sel.to, insert: before + text + after },
    selection: { anchor: sel.from + before.length, head: sel.from + before.length + text.length },
    userEvent: "input",
  });
  view.focus();
}
const fmt = {
  bold: () => wrapSelection("**", "**"),
  italic: () => wrapSelection("*", "*"),
  code: () => wrapSelection("`", "`"),
  strike: () => wrapSelection("~~", "~~"),
  // Шлём прямоугольник выделения (client-координаты) — Swift якорит поповер строго над/под ним.
  link: () => {
    const sel = view.state.selection.main;
    const a = view.coordsAtPos(sel.from), b = view.coordsAtPos(sel.to);
    let rect = null;
    if (a && b) {
      rect = { left: Math.min(a.left, b.left), top: Math.min(a.top, b.top), bottom: Math.max(a.bottom, b.bottom) };
    }
    send({ type: "requestLink", rect });
  },
};

function setLinePrefix(prefix) {
  if (!view) return;
  const line = view.state.doc.lineAt(view.state.selection.main.head);
  const stripped = line.text.replace(/^(\s*)(#{1,6}\s|>\s|[-*+]\s(\[.\]\s)?|\d+\.\s)?/, "$1");
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: prefix + stripped },
    selection: { anchor: line.from + prefix.length + stripped.length },
    userEvent: "input",
  });
  view.focus();
}

// ── Selection toolbar ─────────────────────────────────────────────────────────
let barEl = null;
// Иконка ссылки — контурный SVG (по макету), вместо emoji 🔗.
const LINK_SVG = '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h7v7M13 3L6.5 9.5M11 9.5v3.5H3V5h3.5"/></svg>';

function ensureBar() {
  if (barEl) return barEl;
  barEl = document.createElement("div");
  barEl.className = "sage-seltoolbar";
  // SVG-метки рендерим через innerHTML, текстовые (B/i/</>/S) — через textContent.
  const mk = (label, cls, fn) => { const b = document.createElement("button"); if (label.indexOf("<svg") === 0) b.innerHTML = label; else b.textContent = label; if (cls) b.className = cls; b.onmousedown = (e) => { e.preventDefault(); fn(); }; return b; };
  barEl.append(
    mk("B", "b", fmt.bold), mk("i", "i", fmt.italic), mk("</>", "mono", fmt.code),
    mk("S", "s", fmt.strike), sep(), mk(LINK_SVG, "lnk", fmt.link),
  );
  document.body.appendChild(barEl);
  return barEl;
}
function sep() { const s = document.createElement("div"); s.className = "sep"; return s; }
function hideBar() { if (barEl) barEl.style.display = "none"; }
function updateToolbar() {
  if (!view) return hideBar();
  const sel = view.state.selection.main;
  if (sel.empty) return hideBar();
  const el = ensureBar();
  const a = view.coordsAtPos(sel.from), b = view.coordsAtPos(sel.to);
  if (!a || !b) return hideBar();
  el.style.display = "flex";
  const cx = (a.left + b.right) / 2;
  let top = a.top - 40;
  if (top < 8) top = b.bottom + 8;
  el.style.left = Math.max(8, Math.min(cx - el.offsetWidth / 2, window.innerWidth - el.offsetWidth - 8)) + "px";
  el.style.top = top + "px";
}

// ── Slash-меню ─────────────────────────────────────────────────────────────────
// Локализованные подписи приходят из Swift через window.sageSetStrings (ключи Strings.Slash).
// `label` здесь — РУССКИЙ фолбэк, если мост ещё не отдал строки.
let slashLabels = {};
const slashLabel = (it) => slashLabels[it.key] || it.label;
const SLASH = [
  { ic: "T", key: "blkText", label: "Текст", fn: () => setLinePrefix("") },
  { ic: "H1", key: "blkH1", label: "Заголовок 1", fn: () => setLinePrefix("# ") },
  { ic: "H2", key: "blkH2", label: "Заголовок 2", fn: () => setLinePrefix("## ") },
  { ic: "H3", key: "blkH3", label: "Заголовок 3", fn: () => setLinePrefix("### ") },
  { ic: "•", key: "blkBullet", label: "Список", fn: () => setLinePrefix("- ") },
  { ic: "1.", key: "blkNumbered", label: "Нумерованный", fn: () => setLinePrefix("1. ") },
  { ic: "☐", key: "blkCheck", label: "Чек-лист", fn: () => setLinePrefix("- [ ] ") },
  { ic: "❝", key: "blkQuote", label: "Цитата", fn: () => setLinePrefix("> ") },
  { ic: "▦", key: "blkTable", label: "Таблица", fn: () => { const c = slashLabels.tableColumn || "Колонка"; insertText("| " + c + " | " + c + " |\n| --- | --- |\n|  |  |\n"); } },
  { ic: "</>", key: "blkCode", label: "Код", fn: () => insertText("```\n\n```\n") },
  { ic: "—", key: "blkDivider", label: "Разделитель", fn: () => insertText("\n---\n") },
  { ic: LINK_SVG, key: "blkLink", label: "Ссылка", fn: fmt.link },
];
let slashEl = null, slashOpen = false, slashIndex = 0, slashFrom = -1;
function ensureSlash() {
  if (slashEl) return slashEl;
  slashEl = document.createElement("div");
  slashEl.className = "sage-slash";
  document.body.appendChild(slashEl);
  return slashEl;
}
function renderSlash() {
  const el = ensureSlash();
  el.innerHTML = "";
  SLASH.forEach((it, i) => {
    const row = document.createElement("div");
    row.className = "row" + (i === slashIndex ? " sel" : "");
    const ic = document.createElement("div"); ic.className = "ic";
    if (it.ic.indexOf("<svg") === 0) ic.innerHTML = it.ic; else ic.textContent = it.ic;
    const lb = document.createElement("div"); lb.textContent = slashLabel(it);
    row.append(ic, lb);
    row.onmousedown = (e) => { e.preventDefault(); chooseSlash(i); };
    el.appendChild(row);
  });
  const cur = el.querySelector(".row.sel");
  if (cur) cur.scrollIntoView({ block: "nearest" });
}
function checkSlash() {
  if (!view) return;
  const head = view.state.selection.main.head;
  const line = view.state.doc.lineAt(head);
  const before = line.text.slice(0, head - line.from);
  // Триггерим `/` после любого символа (в т.ч. сразу после буквы слова), КРОМЕ `://` и `//` (URL).
  const m = SLASH_RE.exec(before);
  const slashIdx = m ? before.length - m[0].length : -1;
  const prevCh = slashIdx > 0 ? before[slashIdx - 1] : "";
  if (m && prevCh !== ":" && prevCh !== "/" && view.state.selection.main.empty) {
    slashFrom = head - m[1].length - 1;
    if (!slashOpen) { slashOpen = true; slashIndex = 0; }
    renderSlash();
    const el = ensureSlash(); el.style.display = "block";
    const c = view.coordsAtPos(head);
    if (c) {
      let top = c.bottom + 4; if (top + 300 > window.innerHeight) top = c.top - 304;
      el.style.left = Math.min(c.left, window.innerWidth - 256) + "px"; el.style.top = top + "px";
    }
  } else closeSlash();
}
function closeSlash() { slashOpen = false; slashFrom = -1; if (slashEl) slashEl.style.display = "none"; }
function chooseSlash(i) {
  if (!view) { closeSlash(); return; }
  const head = view.state.selection.main.head;
  if (slashFrom >= 0 && slashFrom < head) {
    view.dispatch({ changes: { from: slashFrom, to: head, insert: "" }, userEvent: "delete" });
  }
  closeSlash();
  setTimeout(() => { view.focus(); SLASH[i].fn(); }, 0);
}

function insertText(text) {
  if (!view) return;
  const sel = view.state.selection.main;
  view.dispatch({ changes: { from: sel.from, to: sel.to, insert: text },
    selection: { anchor: sel.from + text.length }, userEvent: "input" });
  view.focus();
}

// Замена ЗАФИКСИРОВАННОГО маркером диапазона (sage-marksel из markField) — он переживает схлопывание
// живого выделения, пока инлайн-ИИ думает. Иначе «замени» вставлял огрызок в курсор. Нет марки → живое выделение.
function replaceMarked(text) {
  if (!view) return;
  let from = null, to = null;
  const marks = view.state.field(markField, false);
  if (marks) marks.between(0, view.state.doc.length, (f, t) => { from = f; to = t; });
  if (from == null) { const s = view.state.selection.main; from = s.from; to = s.to; }
  view.dispatch({ changes: { from, to, insert: text },
    selection: { anchor: from + text.length }, effects: clearMark.of(null), userEvent: "input" });
  view.focus();
}

// ── Хоткеи / клики / Esc ────────────────────────────────────────────────────
const sageKeymap = keymap.of([
  { key: "Mod-b", run: () => { fmt.bold(); return true; } },
  { key: "Mod-i", run: () => { fmt.italic(); return true; } },
  { key: "Mod-e", run: () => { fmt.code(); return true; } },
  { key: "Mod-j", run: () => { requestAINow(); return true; } },
  { key: "Space", run: (v) => {
    // Двойной пробел после слова → «. » (как в macOS). В коде не срабатывает — точка сломала бы код.
    const s = v.state.selection.main;
    if (!s.empty || s.from < 2) return false;
    if (!autoPeriodBefore(v.state.doc.sliceString(s.from - 2, s.from))) return false;
    for (let n = syntaxTree(v.state).resolveInner(s.from, -1); n; n = n.parent) {
      if (/FencedCode|CodeBlock|InlineCode|CodeText/.test(n.name)) return false;
    }
    v.dispatch({ changes: { from: s.from - 1, to: s.from, insert: ". " },
                 selection: { anchor: s.from + 1 }, userEvent: "input.type" });
    return true;
  } },
  { key: "ArrowDown", run: () => { if (slashOpen) { slashIndex = Math.min(SLASH.length - 1, slashIndex + 1); renderSlash(); return true; } return false; } },
  { key: "ArrowUp", run: () => { if (slashOpen) { slashIndex = Math.max(0, slashIndex - 1); renderSlash(); return true; } return false; } },
  { key: "Enter", run: () => { if (slashOpen) { chooseSlash(slashIndex); return true; } return false; } },
  { key: "Escape", run: () => { if (slashOpen) { closeSlash(); return true; } send({ type: "escape" }); return false; } },
]);

function requestAINow() {
  let selection = "";
  if (view) {
    const s = view.state.selection.main;
    if (!s.empty) {
      selection = view.state.doc.sliceString(s.from, s.to);
      // ФИКСИРУЕМ диапазон маркером ПРЯМО СЕЙЧАС (в момент запроса ИИ) — чтобы replaceMarked
      // заменил именно это выделение, даже если живое выделение потом схлопнется. Иначе «удали/
      // перефразируй» вставляли огрызок в курсор.
      view.dispatch({ effects: setMark.of({ from: s.from, to: s.to }) });
    }
  }
  send({ type: "requestAI", selection });
}

// ── Команды из Swift ─────────────────────────────────────────────────────────
// Preview-режим = blockField (блочные виджеты) + livePreviewPlugin (инлайн/строки);
// Markdown-режим = пусто (сырой текст).
function previewExtensions() { return isLivePreview() ? [blockField, livePreviewPlugin] : []; }

// ── Анти-фантомное-выделение ──────────────────────────────────────────────────
// Симптом (рекуррентный): ОДИНОЧНЫЙ тап по пустой области → выделялась «нижняя половина» текста
// (диапазон от залипшего/нативного якоря к концу). Источник на уровне WKWebView/CM6 неуловим точечно,
// поэтому ловим по СИМПТОМУ: одиночный плоский клик (НЕ drag, НЕ dbl/triple) НИКОГДА не должен оставлять
// диапазон — схлопываем к позиции клика. Настоящий drag-select (сдвиг>3px) и dbl/triple (слово/строка) целы.
let clickDownX = 0, clickDownY = 0;
const collapsePhantomSelection = EditorView.domEventHandlers({
  mousedown(e) { clickDownX = e.clientX; clickDownY = e.clientY; return false; },
  click(e, view) {
    const sel = view.state.selection.main;
    if (!shouldCollapseClick(e.button, e.detail, e.clientX - clickDownX, e.clientY - clickDownY, sel.empty)) return false;
    const at = view.posAtCoords({ x: e.clientX, y: e.clientY }, false);
    view.dispatch({ selection: { anchor: at ?? sel.head, head: at ?? sel.head } });       // схлопнуть фантом к клику
    return false;
  },
});

function makeState(doc) {
  const md = doc || "";
  return EditorState.create({
    doc: md,
    selection: { anchor: bodyStartOffset(md) },
    extensions: [
      history(),
      drawSelection(),
      dropCursor(),
      collapsePhantomSelection,   // одиночный плоский клик не оставляет фантомный диапазон
      EditorView.lineWrapping,
      markdown({ base: markdownLanguage }),
      previewCompartment.of(previewExtensions()),
      focusField,
      // CM6 сам диспатчит setFocus при смене фокуса (без ручного dispatch в updateListener).
      EditorView.focusChangeEffect.of((_state, focusing) => setFocus.of(focusing)),
      markField,
      baseTheme,
      sageKeymap,
      keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
      updateListener,
    ],
  });
}

window.sageSetDoc = (md, epoch) => {
  if (typeof epoch === "number") currentEpoch = epoch;
  if (!view) return;
  if (docTimer) { clearTimeout(docTimer); docTimer = null; }
  docFirstPendingAt = 0;
  suppress = true;
  // НОВЫЙ state → undo-история пустая (нет отката к содержимому прошлого файла).
  view.setState(makeState(md || ""));
  // Снимаем фокус при открытии → ничего не раскрыто, всё отрендерено чисто (reading-режим).
  try { view.contentDOM.blur(); } catch (e) {}
  // Допарсить документ синхронно (бюджет 100мс), чтобы блоки (callout/таблица) ниже первых ~3КБ
  // отрендерились СРАЗУ на открытии, а не после клика/скролла. forceParsing сам делает dispatch →
  // blockField пересчитается. Остаток (для очень больших файлов) дочитает фоновый воркер.
  try { forceParsing(view, view.state.doc.length, 100); } catch (e) {}
  setTimeout(() => { suppress = false; }, 30);
};
window.sageSetMode = (mode) => {
  setLivePreview(mode !== "markdown");
  if (view) view.dispatch({ effects: previewCompartment.reconfigure(previewExtensions()) });
};
window.sageSetTheme = (vars) => {
  try { const o = (typeof vars === "string") ? JSON.parse(vars) : vars;
    for (const k in o) document.documentElement.style.setProperty(k, o[k]); } catch (e) {}
  // Смена темы/акцента → пересчитать высоты виджетов (иначе картинка теряет отрисовку).
  try { if (view) setTimeout(() => view.requestMeasure(), 20); } catch (e) {}
};
window.sageScrollToHeading = (text) => {
  if (!view || !text) return;
  const want = text.trim().toLowerCase();
  const total = view.state.doc.lines;
  for (let n = 1; n <= total; n++) {
    const line = view.state.doc.line(n);
    const m = /^#{1,6}\s+(.*)$/.exec(line.text);
    if (m && m[1].trim().toLowerCase() === want) {
      // Плавный доскролл (анимированный) вместо мгновенного scrollIntoView.
      const top = view.lineBlockAt(line.from).top;
      view.scrollDOM.scrollTo({ top: Math.max(0, top - 12), behavior: "smooth" });
      return;
    }
  }
};
window.sageScrollToLine = () => {};
// Локализованные подписи слэш-меню (из Swift Strings.Slash) — иначе пункты были захардкожены по-русски.
window.sageSetStrings = (s) => {
  try { slashLabels = (typeof s === "string") ? JSON.parse(s) : (s || {}); } catch (e) { slashLabels = {}; }
  if (slashOpen) renderSlash();
};
window.sageMarkSelection = () => { if (!view) return; const s = view.state.selection.main; if (s.from !== s.to) view.dispatch({ effects: setMark.of({ from: s.from, to: s.to }) }); };
window.sageClearMark = () => { if (view) view.dispatch({ effects: clearMark.of(null) }); };
window.sageFocus = () => { try { view && view.focus(); } catch (e) {} };
window.sageReplaceSelection = (text) => replaceMarked(text);
window.sageInsertAtCursor = (text) => insertText(text);
// Вставить готовую строку (markdown-ссылку, собранную в Swift) — заменяет выделение/вставляет в курсор.
window.sageInsertText = (text) => insertText(text);
window.sageInsertLink = (title, path) => {
  // Если есть выделение — оно становится лейблом ссылки (а не подменяется именем файла).
  const sel = view ? view.state.selection.main : null;
  const selText = sel ? view.state.doc.sliceString(sel.from, sel.to) : "";
  insertText(linkMarkdown(selText, title, path));
};
window.sageInsertImage = (rel) => insertText("\n![](" + rel + ")\n");
// Немедленно отправить текущий документ (минуя debounce) — для критичных правок (вставка картинки).
window.sageFlushDoc = () => {
  if (!view) return;
  if (docTimer) { clearTimeout(docTimer); docTimer = null; }
  docFirstPendingAt = 0;
  send({ type: "doc", text: view.state.doc.toString(), epoch: currentEpoch, flush: true });
};
// Прямое чтение текущего документа Swift-стороной (RPC, минуя debounce). Эпоха — для валидации
// на приёме: ответ, прилетевший после следующего setDoc, относится к ЧУЖОМУ документу.
window.sageGetDoc = () => view ? ({ text: view.state.doc.toString(), epoch: currentEpoch }) : null;
window.sageSetBase = (p) => { setBaseFolder(p); if (view) view.dispatch({ effects: previewCompartment.reconfigure(previewExtensions()) }); };

// ── Клики по ссылкам + вставка/дроп картинок ─────────────────────────────────
rootEl.addEventListener("mousedown", (e) => {
  const a = e.target.closest && e.target.closest("[data-href]");
  if (a && a.getAttribute("data-href")) { e.preventDefault(); send({ type: "openLink", href: a.getAttribute("data-href") }); return; }
  // НЕ диспатчим clearMark здесь: транзакция в capture-фазе ДО обработки клика CM6 сбивала якорь
  // drag-select → «выделялась половина текста». Марка снимается штатно в markField на selection-change клика.
}, true);

function sendImageFile(file, type) {
  const reader = new FileReader();
  reader.onload = () => {
    const b64 = String(reader.result).split(",")[1] || "";
    const ext = (type || file.type || "image/png").split("/")[1] || "png";
    if (b64) send({ type: "insertImage", b64, ext });
  };
  reader.readAsDataURL(file);
}
rootEl.addEventListener("paste", (e) => {
  const items = e.clipboardData && e.clipboardData.items; if (!items) return;
  for (const it of items) if (it.kind === "file" && it.type.indexOf("image/") === 0) {
    const f = it.getAsFile(); if (f) { e.preventDefault(); sendImageFile(f, it.type); return; }
  }
}, true);
rootEl.addEventListener("drop", (e) => {
  const files = e.dataTransfer && e.dataTransfer.files; if (!files || !files.length) return;
  for (const f of files) if (f.type && f.type.indexOf("image/") === 0) { e.preventDefault(); sendImageFile(f, f.type); return; }
}, true);
window.addEventListener("scroll", () => updateToolbar(), true);

// ── Инициализация ────────────────────────────────────────────────────────────
view = new EditorView({ state: makeState(""), parent: rootEl });
send({ type: "ready" });
