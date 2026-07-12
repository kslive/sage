// Sage editor — ОБЩАЯ (тестируемая) логика CodeMirror 6 Live Preview.
// Чистые функции + регэкспы + виджеты + builder'ы декораций + CM6-расширения.
// БЕЗ top-level DOM/window side-effects → импортируется в Node-тестах (node:test, jsdom для toDOM).
// Бридж Swift↔webview, DOM-листенеры и инициализация view — в codemirror.js (entry).
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view";
import { StateField, StateEffect } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";

// ── Изменяемое состояние (выставляет entry: sageSetMode/sageSetBase) ──────────
let _livePreview = true;     // Preview (Live Preview) vs Markdown (сырой)
export const isLivePreview = () => _livePreview;
export const setLivePreview = (v) => { _livePreview = v; };
let _baseFolder = "";
export const setBaseFolder = (p) => { _baseFolder = p || ""; };

// ── Регэкспы (экспортируем для тестов; функции ниже используют ИХ ЖЕ) ─────────
export const FRONTMATTER_RE = /^---\s*$/;
export const HEADING_PREFIX_RE = /^#{1,6}\s/;
export const CALLOUT_RE = /^\s*>\s*\[!(\w+)\]/i;             // детект callout
export const CALLOUT_FULL_RE = /^\s*>\s*\[!(\w+)\][+-]?\s*(.*)$/i; // тип + (fold) + заголовок
export const TASK_RE = /^(\s*)([-*+])\s+\[([ xX])\]\s/;
export const BULLET_RE = /^(\s*)([-*+])\s/;
export const FM_KV_RE = /^([\w.$-]+)\s*:\s*(.*)$/;
export const SLASH_RE = /\/(\w*)$/;

export const HEADING = { ATXHeading1: "ln-h1", ATXHeading2: "ln-h2", ATXHeading3: "ln-h3",
  ATXHeading4: "ln-h4", ATXHeading5: "ln-h4", ATXHeading6: "ln-h4" };

// Иконка и цветовая группа по типу callout (как в Obsidian).
export const CALLOUT_ICON = {
  note: "✏️", info: "ℹ️", todo: "☑️", abstract: "📋", summary: "📋", tldr: "📋",
  tip: "🔥", hint: "🔥", important: "🔥", success: "✅", check: "✅", done: "✅",
  question: "❓", help: "❓", faq: "❓", warning: "⚠️", caution: "⚠️", attention: "⚠️",
  failure: "❌", fail: "❌", missing: "❌", danger: "⚡", error: "⚡", bug: "🐛",
  example: "📑", quote: "💬", cite: "💬",
};
export const CALLOUT_GROUP = {
  note: "note", info: "note", todo: "note", abstract: "abstract", summary: "abstract", tldr: "abstract",
  tip: "tip", hint: "tip", important: "tip", success: "success", check: "success", done: "success",
  question: "question", help: "question", faq: "question", warning: "warning", caution: "warning", attention: "warning",
  failure: "fail", fail: "fail", missing: "fail", danger: "danger", error: "danger", bug: "danger",
  example: "example", quote: "quote", cite: "quote",
};
export function calloutIcon(t) { return CALLOUT_ICON[t] || "📌"; }
export function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

export function escapeHtml(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
// Мини-рендер инлайн-markdown → HTML (жирный/курсив/код/зачёркнутый/ссылки).
// Работает на уже экранированной строке (поэтому ссылка <url> ищется как &lt;url&gt;).
export function renderInline(src) {
  let s = escapeHtml(src);
  s = s.replace(/`([^`]+)`/g, (_, c) => `<code class="tok-code">${c}</code>`);
  s = s.replace(/\[([^\]]+)\]\(&lt;([^&]+)&gt;\)/g, (_, t, u) => `<a class="tok-link" data-href="${u}">${t}</a>`);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, t, u) => `<a class="tok-link" data-href="${u}">${t}</a>`);
  s = s.replace(/\*\*([^*]+?)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/__([^_]+?)__/g, "<strong>$1</strong>");
  s = s.replace(/\*([^*\n]+?)\*/g, "<em>$1</em>");
  s = s.replace(/~~([^~]+?)~~/g, "<del>$1</del>");
  return s;
}
export function renderCalloutBody(lines) {
  let html = "", inList = false;
  for (const ln of lines) {
    const li = /^\s*[-*+]\s+(.*)$/.exec(ln);
    if (li) { if (!inList) { html += "<ul class='cm-callout-ul'>"; inList = true; } html += "<li>" + renderInline(li[1]) + "</li>"; continue; }
    if (inList) { html += "</ul>"; inList = false; }
    if (ln.trim() === "") { html += "<div class='cm-callout-sp'></div>"; continue; }
    html += "<div>" + renderInline(ln) + "</div>";
  }
  if (inList) html += "</ul>";
  return html;
}
export function parseAligns(line) {
  const segs = line.split("|").map((s) => s.trim());
  if (segs.length && segs[0] === "") segs.shift();
  if (segs.length && segs[segs.length - 1] === "") segs.pop();
  return segs.map((seg) => {
    const l = seg.startsWith(":"), r = seg.endsWith(":");
    return l && r ? "center" : r ? "right" : "left";
  });
}
export function collectCells(state, syntaxNode, out) {
  const cur = syntaxNode.cursor();
  if (cur.firstChild()) {
    do { if (cur.name === "TableCell") out.push(state.doc.sliceString(cur.from, cur.to).trim()); } while (cur.nextSibling());
  }
}
// Смещение начала тела (после закрывающего --- frontmatter), иначе 0.
export function bodyStartOffset(text) {
  if (!text || !FRONTMATTER_RE.test(text.split("\n", 1)[0] || "")) return 0;
  const lines = text.split("\n");
  for (let i = 1; i < lines.length; i++) {
    if (FRONTMATTER_RE.test(lines[i])) {
      let off = 0;
      for (let j = 0; j <= i; j++) off += lines[j].length + 1;  // +1 — перенос строки
      return Math.min(off, text.length);
    }
  }
  return 0;
}
// Решение toggle-форматирования (Notion-стиль): маркеры внутри выделения / вокруг / нет.
export function decideToggle(text, pre, post, before, after) {
  if (text.length >= before.length + after.length && text.startsWith(before) && text.endsWith(after)) return "inside";
  if (pre === before && post === after) return "around";
  return "wrap";
}
// Markdown-ссылки: выделение→лейбл (иначе title/«ссылка»); пробелы в пути → <...> (CommonMark).
// Чистое: [label](dest); пробелы в dest → <...> (CommonMark). Метка — явная (из поля «Текст»).
export function buildLink(label, path) {
  const t = (label || "ссылка").replace(/[\[\]]/g, "").trim() || "ссылка";
  const p = path || "";
  const dest = /\s/.test(p) ? "<" + p + ">" : p;
  return "[" + t + "](" + dest + ")";
}
export function linkMarkdown(selText, title, path) {
  return buildLink((selText || "").trim() || title, path);
}
// Картинки заметки → схема sageimg://local/<abs> (index.html из бандла, относительные не резолвятся).
export function imgSrcToScheme(rel) {
  if (!rel || /^(sageimg:|https?:|data:|file:|blob:)/i.test(rel)) return rel;
  if (!_baseFolder) return rel;
  const abs = _baseFolder.replace(/\/+$/, "") + "/" + rel.replace(/^\.\//, "");
  return "sageimg://local/" + encodeURIComponent(abs);
}

// Решение «схлопнуть фантомное выделение»: ОДИНОЧНЫЙ левый клик (detail==1) БЕЗ перетаскивания
// (|dx|,|dy| ≤ 3) при НЕпустом выделении → схлопнуть к курсору. Drag-select, dbl/triple, правый клик — не трогаем.
// Чистая фн (тест) — корень фантомных выделений «тап → выделялась половина текста».
export function shouldCollapseClick(button, detail, dx, dy, selectionEmpty) {
  if (button !== 0 || detail !== 1) return false;
  if (Math.abs(dx) > 3 || Math.abs(dy) > 3) return false;
  return !selectionEmpty;
}

// ── Клик по блок-виджету (не по ссылке) → каретка в блок → перерисовка покажет сырой markdown.
function attachReveal(el, view) {
  el.addEventListener("mousedown", (e) => {
    if (e.target.closest && e.target.closest("[data-href]")) return;
    e.preventDefault();
    const pos = view.posAtDOM(el);
    // Явно ПУСТОЕ выделение (anchor==head) + снять висящую sage-марку: иначе клик «выделял» текст.
    view.dispatch({ selection: { anchor: pos, head: pos }, effects: clearMark.of(null) });
    setTimeout(() => view.focus(), 0);
  });
}
// Внешняя обёртка блок-виджета: вертикальный ритм через PADDING (не margin) — CM6 меряет
// высоту виджета без margin (offsetHeight), и margin ломал карту высот → клик мапился ниже.
function blockWrap(inner, view) {
  const w = document.createElement("div");
  w.className = "cm-bw";
  w.appendChild(inner);
  attachReveal(w, view);
  return w;
}

export class ImageWidget extends WidgetType {
  constructor(src) { super(); this.src = src; }
  eq(o) { return o.src === this.src; }
  toDOM(view) {
    const img = document.createElement("img");
    img.src = imgSrcToScheme(this.src);
    img.style.maxWidth = "100%"; img.style.borderRadius = "8px"; img.style.display = "block";
    img.style.margin = "6px 0";
    // Картинка грузится async — CM мерит высоту виджета ДО загрузки и не перерисовывает
    // (картинка пустая до клика). По onload форсим пересчёт высот (с задержкой — дать DOM приклеиться).
    img.addEventListener("load", () => { try { if (view) setTimeout(() => view.requestMeasure(), 10); } catch (e) {} });
    return img;
  }
}
// Чекбокс задачи (- [ ] / - [x]) — кликабельный (тоггл).
export class CheckboxWidget extends WidgetType {
  constructor(checked) { super(); this.checked = checked; }
  eq(o) { return o.checked === this.checked; }
  toDOM(view) {
    const b = document.createElement("span");
    b.className = "cm-checkbox" + (this.checked ? " cm-checkbox-on" : "");
    b.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const line = view.state.doc.lineAt(view.posAtDOM(b));
      const m = /^(\s*[-*+]\s+\[)([ xX])(\])/.exec(line.text);
      if (m) {
        const at = line.from + m[1].length;
        view.dispatch({ changes: { from: at, to: at + 1, insert: m[2] === " " ? "x" : " " }, userEvent: "input" });
      }
    });
    return b;
  }
}
// Маркер списка → точка по центру.
export class BulletWidget extends WidgetType {
  eq() { return true; }
  toDOM() { const s = document.createElement("span"); s.className = "cm-bullet"; s.textContent = "•"; return s; }
}
// Код-блок как в Notion: единый скруглённый блок, ограждения ``` скрыты, опц. лейбл языка.
// Reveal-по-курсору (как callout/таблица): курсор в блоке → блок не рисуется, видна сырая разметка.
export class CodeWidget extends WidgetType {
  constructor(lang, code) { super(); this.lang = lang || ""; this.code = code; }
  eq(o) { return o.lang === this.lang && o.code === this.code; }
  toDOM(view) {
    const box = document.createElement("div");
    box.className = "cm-code-block";
    if (this.lang) {
      const lab = document.createElement("div");
      lab.className = "cm-code-label";
      lab.textContent = this.lang;
      box.appendChild(lab);
    }
    const pre = document.createElement("pre");
    pre.className = "cm-code-content";
    pre.textContent = this.code;
    box.appendChild(pre);
    return blockWrap(box, view);
  }
}
// Горизонтальный разделитель (--- / *** / ___) → настоящая линия.
export class HrWidget extends WidgetType {
  eq() { return true; }
  toDOM(view) { const d = document.createElement("div"); d.className = "cm-hr"; return blockWrap(d, view); }
}
export class CalloutWidget extends WidgetType {
  constructor(type, title, body) { super(); this.type = type; this.title = title; this.body = body; }
  eq(o) { return o.type === this.type && o.title === this.title && o.body.join("\n") === this.body.join("\n"); }
  toDOM(view) {
    const grp = CALLOUT_GROUP[this.type] || "note";
    const box = document.createElement("div");
    box.className = "cm-callout cm-cg-" + grp;
    const head = document.createElement("div");
    head.className = "cm-callout-head";
    head.innerHTML = `<span class="cm-callout-ic">${calloutIcon(this.type)}</span>` +
      `<span class="cm-callout-title">${this.title ? renderInline(this.title) : cap(this.type)}</span>`;
    box.appendChild(head);
    const body = this.body.slice();
    while (body.length && body[body.length - 1].trim() === "") body.pop();
    if (body.some((l) => l.trim() !== "")) {
      const bd = document.createElement("div");
      bd.className = "cm-callout-body";
      bd.innerHTML = renderCalloutBody(body);
      box.appendChild(bd);
    }
    return blockWrap(box, view);
  }
}
export class TableWidget extends WidgetType {
  constructor(header, rows, aligns) { super(); this.header = header; this.rows = rows; this.aligns = aligns || []; }
  eq(o) { return JSON.stringify([o.header, o.rows]) === JSON.stringify([this.header, this.rows]); }
  toDOM(view) {
    const al = (i) => this.aligns[i] || "left";
    const wrap = document.createElement("div");
    wrap.className = "cm-md-tablewrap";
    const t = document.createElement("table");
    t.className = "cm-md-table";
    if (this.header.length) {
      const thead = document.createElement("thead");
      const tr = document.createElement("tr");
      this.header.forEach((c, i) => { const th = document.createElement("th"); th.style.textAlign = al(i); th.innerHTML = renderInline(c); tr.appendChild(th); });
      thead.appendChild(tr); t.appendChild(thead);
    }
    const tb = document.createElement("tbody");
    this.rows.forEach((r) => {
      const tr = document.createElement("tr");
      r.forEach((c, i) => { const td = document.createElement("td"); td.style.textAlign = al(i); td.innerHTML = renderInline(c); tr.appendChild(td); });
      tb.appendChild(tr);
    });
    t.appendChild(tb); wrap.appendChild(t);
    return blockWrap(wrap, view);
  }
}
export class FrontmatterWidget extends WidgetType {
  constructor(rows) { super(); this.rows = rows; }
  eq(o) { return JSON.stringify(o.rows) === JSON.stringify(this.rows); }
  toDOM(view) {
    const box = document.createElement("div");
    box.className = "cm-frontmatter";
    const cap2 = document.createElement("div");
    cap2.className = "cm-fm-cap"; cap2.textContent = "Свойства";
    box.appendChild(cap2);
    this.rows.forEach(([k, val]) => {
      const row = document.createElement("div"); row.className = "cm-fm-row";
      const ke = document.createElement("span"); ke.className = "cm-fm-key"; ke.textContent = k;
      const ve = document.createElement("span"); ve.className = "cm-fm-val"; ve.textContent = val;
      row.append(ke, ve); box.appendChild(row);
    });
    return blockWrap(box, view);
  }
}

function lineClass(v, decos, pos, cls) { lnClass(decos, v.state.doc.lineAt(pos), cls); }
function lnClass(decos, line, cls) { decos.push(Decoration.line({ class: cls }).range(line.from)); }
function eachLine(v, from, to, fn) {
  let n = v.state.doc.lineAt(from).number;
  const end = v.state.doc.lineAt(to).number;
  for (; n <= end; n++) fn(v.state.doc.line(n));
}
function hideMarksInside(v, node, markName, active, hide) {
  const line = v.state.doc.lineAt(node.from);
  if (active.has(line.number)) return;
  const cur = node.node.cursor();
  if (cur.firstChild()) {
    do { if (cur.name === markName) hide(cur.from, cur.to); } while (cur.nextSibling());
  }
}

// ── ИИ-подсветка выделения (sageMarkSelection) ───────────────────────────────
export const setMark = StateEffect.define();
export const clearMark = StateEffect.define();
export const markField = StateField.define({
  create() { return Decoration.none; },
  update(deco, tr) {
    // Эффекты имеют приоритет: setMark ставит марку (диспатчится БЕЗ смены выделения),
    // clearMark/replaceMarked — снимают.
    for (const e of tr.effects) {
      if (e.is(setMark)) {
        const { from, to } = e.value;
        return (to > from)
          ? Decoration.set([Decoration.mark({ class: "sage-marksel" }).range(from, to)])
          : Decoration.none;
      }
      if (e.is(clearMark)) return Decoration.none;
    }
    // ЛЮБОЙ пользовательский сдвиг каретки/новое выделение (клик, стрелки) снимает марку —
    // иначе подсветка sage-marksel «залипала» и выглядела как выделение пол-текста.
    if (tr.selection) return Decoration.none;
    return deco.map(tr.changes);
  },
  provide: (f) => EditorView.decorations.from(f),
});

// ── Фокус-состояние (для blockField): раскрытие блоков работает только в фокусе.
// При открытии файла редактор не в фокусе → всё отрендерено чисто (reading-режим Obsidian).
export const setFocus = StateEffect.define();
export const focusField = StateField.define({
  create() { return false; },
  update(val, tr) {
    for (const e of tr.effects) if (e.is(setFocus)) return e.value;
    return val;
  },
});

// ── Live Preview: инлайн/строчные декорации поверх СЫРОГО текста (текст не меняется) ──
export function buildDecorations(viewArg) {
  const decos = [];
  if (!_livePreview) return Decoration.none;
  const v = viewArg;
  // Строки с кареткой/выделением раскрываются (сырые маркеры) — ТОЛЬКО когда редактор в фокусе.
  const active = new Set();
  if (v.hasFocus) {
    for (const r of v.state.selection.ranges) {
      const a = v.state.doc.lineAt(r.from).number, b = v.state.doc.lineAt(r.to).number;
      for (let n = a; n <= b; n++) active.add(n);
    }
  }
  const lineActive = (pos) => active.has(v.state.doc.lineAt(pos).number);
  const blockActive = (from, to) => {
    const fn = v.state.doc.lineAt(from).number, tn = v.state.doc.lineAt(to).number;
    for (let n = fn; n <= tn; n++) if (active.has(n)) return true;
    return false;
  };
  // Кламп в пределах строки: плагин НЕ должен порождать replace через перенос строки —
  // CM6 это запрещает из ViewPlugin и роняет ВЕСЬ набор (view/dist:2738).
  const hide = (from, to) => {
    if (to <= from) return;
    const lineEnd = v.state.doc.lineAt(from).to;
    const t = Math.min(to, lineEnd);
    if (t > from) decos.push(Decoration.replace({}).range(from, t));
  };
  const mark = (from, to, cls, attrs) => {
    if (to > from) decos.push(Decoration.mark({ class: cls, attributes: attrs }).range(from, to));
  };

  // Frontmatter рисует blockField (панель «Свойства»), когда не раскрыт кареткой. Здесь вычисляем
  // fmEnd, чтобы плагин не decorировал скрытые строки (block из плагина CM6 запрещён).
  let fmEnd = 0;
  if (v.state.doc.lines >= 2 && FRONTMATTER_RE.test(v.state.doc.line(1).text)) {
    let end = 0;
    for (let n = 2; n <= v.state.doc.lines; n++) {
      if (FRONTMATTER_RE.test(v.state.doc.line(n).text)) { end = n; break; }
    }
    if (end >= 2) {
      const fStop = v.state.doc.line(end).to;
      if (!blockActive(v.state.doc.line(1).from, fStop)) fmEnd = fStop;
    }
  }

  try {
    for (const { from, to } of v.visibleRanges) {
      const tree = syntaxTree(v.state);
      tree.iterate({
        from, to,
        enter: (node) => {
          const name = node.name;
          const a = node.from, b = node.to;
          // Пропускаем только узлы ЦЕЛИКОМ внутри скрытого frontmatter. Нельзя `a < fmEnd`:
          // корневой Document начинается с 0 → пропустился бы весь документ (decos=0).
          if (fmEnd > 0 && b <= fmEnd) return false;
          if (HEADING[name]) {
            lineClass(v, decos, a, HEADING[name]);
            const line = v.state.doc.lineAt(a);
            if (!active.has(line.number)) {
              const m = HEADING_PREFIX_RE.exec(line.text);
              if (m) hide(line.from, line.from + m[0].length);
            }
            return;
          }
          if (name === "Blockquote") {
            // Callout рисует blockField ЦЕЛИКОМ (активный — сырым текстом). Плагин внутрь не лезет.
            if (CALLOUT_RE.test(v.state.doc.lineAt(a).text)) return false;
            eachLine(v, a, b, (ln) => lnClass(decos, ln, "ln-quote"));
            return;
          }
          if (name === "Table") return false;   // рисует blockField
          if (name === "FencedCode") {
            const first = v.state.doc.lineAt(a).number, last = v.state.doc.lineAt(b).number;
            eachLine(v, a, b, (ln) => {
              let cls = "ln-code";
              if (ln.number === first) cls += " ln-code-first";
              if (ln.number === last) cls += " ln-code-last";
              lnClass(decos, ln, cls);
            });
            return;
          }
          if (name === "HorizontalRule") {
            if (!lineActive(a)) return;          // не активна → field рисует линию <hr>
            lineClass(v, decos, a, "ln-hr");     // активна → сырой ---
            return;
          }
          if (name === "ListItem") {
            const line = v.state.doc.lineAt(a);
            if (!active.has(line.number)) {
              const task = TASK_RE.exec(line.text);
              if (task) {
                const s = line.from + task[1].length, e = line.from + task[0].length;
                decos.push(Decoration.replace({ widget: new CheckboxWidget(task[3].toLowerCase() === "x") }).range(s, e));
              } else {
                const bul = BULLET_RE.exec(line.text);
                if (bul) {
                  const s = line.from + bul[1].length;
                  decos.push(Decoration.replace({ widget: new BulletWidget() }).range(s, s + 1));
                }
              }
            }
            return;
          }
          if (name === "StrongEmphasis") { mark(a, b, "tok-strong"); hideMarksInside(v, node, "EmphasisMark", active, hide); return; }
          if (name === "Emphasis") { mark(a, b, "tok-em"); hideMarksInside(v, node, "EmphasisMark", active, hide); return; }
          if (name === "Strikethrough") { mark(a, b, "tok-strike"); hideMarksInside(v, node, "StrikethroughMark", active, hide); return; }
          if (name === "InlineCode") {
            mark(a, b, "tok-code");
            if (!lineActive(a)) hideMarksInside(v, node, "CodeMark", active, hide);
            return;
          }
          if (name === "Image") {
            const text = v.state.doc.sliceString(a, b);
            const m = /\!\[[^\]]*\]\(([^)]+)\)/.exec(text);
            if (m && !lineActive(a) && v.state.doc.lineAt(a).number === v.state.doc.lineAt(b).number) {
              decos.push(Decoration.replace({ widget: new ImageWidget(m[1]) }).range(a, b));
            }
            return;
          }
          if (name === "Link") {
            const text = v.state.doc.sliceString(a, b);
            const m = /^\[([^\]]*)\]\(([^)]+)\)/.exec(text);
            if (m && !lineActive(a)) {
              const labelStart = a + 1, labelEnd = a + 1 + m[1].length;
              hide(a, labelStart);                    // [
              mark(labelStart, labelEnd, "tok-link", { "data-href": m[2] });
              hide(labelEnd, b);                       // ](url)
            } else {
              mark(a, b, "tok-link", { "data-href": m ? m[2] : "" });
            }
            return;
          }
        },
      });
    }
  } catch (e) { return Decoration.none; }
  decos.sort((x, y) => x.from - y.from || x.value.startSide - y.value.startSide);
  try { return Decoration.set(decos, true); } catch (e) { return Decoration.none; }
}

export const livePreviewPlugin = ViewPlugin.fromClass(class {
  constructor(v) { this.decorations = buildDecorations(v); }
  update(u) {
    if (u.docChanged || u.viewportChanged || u.selectionSet || u.focusChanged ||
        syntaxTree(u.state) !== syntaxTree(u.startState) ||
        u.transactions.some((t) => t.reconfigured)) {
      this.decorations = buildDecorations(u.view);
    }
  }
}, { decorations: (p) => p.decorations });

// Блочные декорации (callout / таблица / frontmatter / hr) — ТОЛЬКО через StateField:
// CM6 запрещает декорации, заменяющие переносы строк, из ViewPlugin.
export function buildBlockDecorations(state) {
  if (!_livePreview) return Decoration.none;
  const decos = [];
  // Блок раскрывается (сырой markdown) только если редактор в фокусе И каретка в блоке.
  const active = new Set();
  if (state.field(focusField, false)) {
    for (const r of state.selection.ranges) {
      const a = state.doc.lineAt(r.from).number, b = state.doc.lineAt(r.to).number;
      for (let n = a; n <= b; n++) active.add(n);
    }
  }
  const blockActive = (from, to) => {
    const fn = state.doc.lineAt(from).number, tn = state.doc.lineAt(to).number;
    for (let n = fn; n <= tn; n++) if (active.has(n)) return true;
    return false;
  };
  let fmStop = 0;  // конец frontmatter — узлы дерева до него пропускаем (его рисует FrontmatterWidget)
  try {
    if (state.doc.lines >= 2 && FRONTMATTER_RE.test(state.doc.line(1).text)) {
      let end = 0;
      for (let n = 2; n <= state.doc.lines; n++) { if (FRONTMATTER_RE.test(state.doc.line(n).text)) { end = n; break; } }
      if (end >= 2) {
        const fStart = state.doc.line(1).from, fStop = state.doc.line(end).to;
        fmStop = fStop;   // даже если активен (сырой) — узлы (--- как HorizontalRule) тут не рисуем виджетами
        if (!blockActive(fStart, fStop)) {
          const rows = [];
          for (let n = 2; n < end; n++) {
            const m = FM_KV_RE.exec(state.doc.line(n).text);
            if (m) rows.push([m[1], m[2]]);
          }
          decos.push(Decoration.replace({ widget: new FrontmatterWidget(rows), block: true }).range(fStart, fStop));
        }
      }
    }
    // Callouts + таблицы + hr — по верхнеуровневым блокам дерева (раскрытие по каретке).
    const cur = syntaxTree(state).cursor();
    if (cur.firstChild()) {
      do {
        const name = cur.name, a = cur.from, b = cur.to;
        if (fmStop > 0 && a < fmStop) continue;   // внутри frontmatter — пропускаем
        if (name === "Blockquote") {
          const firstLine = state.doc.lineAt(a);
          const cm = CALLOUT_FULL_RE.exec(firstLine.text);
          if (cm && !blockActive(a, b)) {
            const type = cm[1].toLowerCase(), title = cm[2].trim();
            const lastNum = state.doc.lineAt(b).number;
            const body = [];
            for (let n = firstLine.number + 1; n <= lastNum; n++) body.push(state.doc.line(n).text.replace(/^\s*>\s?/, ""));
            decos.push(Decoration.replace({ widget: new CalloutWidget(type, title, body), block: true })
              .range(firstLine.from, state.doc.line(lastNum).to));
          }
        } else if (name === "Table") {
          if (!blockActive(a, b)) {
            const header = [], rows = [];
            const tc = cur.node.cursor();
            if (tc.firstChild()) {
              do {
                if (tc.name === "TableHeader") collectCells(state, tc.node, header);
                else if (tc.name === "TableRow") { const r = []; collectCells(state, tc.node, r); if (r.length) rows.push(r); }
              } while (tc.nextSibling());
            }
            const secondLine = state.doc.lineAt(a).number + 1;
            const aligns = secondLine <= state.doc.lines ? parseAligns(state.doc.line(secondLine).text) : [];
            decos.push(Decoration.replace({ widget: new TableWidget(header, rows, aligns), block: true })
              .range(state.doc.lineAt(a).from, state.doc.lineAt(b).to));
          }
        } else if (name === "HorizontalRule") {
          if (!blockActive(a, b)) {
            decos.push(Decoration.replace({ widget: new HrWidget(), block: true })
              .range(state.doc.lineAt(a).from, state.doc.lineAt(b).to));
          }
        } else if (name === "FencedCode") {
          if (!blockActive(a, b)) {
            const firstLine = state.doc.lineAt(a), lastLine = state.doc.lineAt(b);
            const lm = /^```\s*([\w+#.-]*)/.exec(firstLine.text);
            const lang = lm ? lm[1] : "";
            const codeLines = [];
            for (let n = firstLine.number + 1; n < lastLine.number; n++) codeLines.push(state.doc.line(n).text);
            decos.push(Decoration.replace({ widget: new CodeWidget(lang, codeLines.join("\n")), block: true })
              .range(firstLine.from, lastLine.to));
          }
        }
      } while (cur.nextSibling());
    }
  } catch (e) { return Decoration.none; }
  decos.sort((x, y) => x.from - y.from || x.value.startSide - y.value.startSide);
  try { return Decoration.set(decos, true); } catch (e) { return Decoration.none; }
}

export const blockField = StateField.define({
  create(state) { return buildBlockDecorations(state); },
  update(deco, tr) {
    const focusChanged = tr.effects.some((e) => e.is(setFocus));
    if (tr.docChanged || tr.selection || focusChanged || syntaxTree(tr.state) !== syntaxTree(tr.startState))
      return buildBlockDecorations(tr.state);
    return deco.map(tr.changes);
  },
  provide: (f) => EditorView.decorations.from(f),
});

// ── Тема (layout колонки задаём ЗДЕСЬ: база CM6 идёт через ͼ-обёртку и перебивает index.html) ──
export const baseTheme = EditorView.theme({
  "&": { color: "var(--tx)", backgroundColor: "transparent", height: "100%" },
  ".cm-scroller": { justifyContent: "center" },
  ".cm-content": {
    fontFamily: "'General Sans',-apple-system,sans-serif",
    fontSize: "15px",
    flexGrow: "0",          // отменяем flexGrow:2 базы → колонка не растягивается
    flexShrink: "1",        // на узких окнах колонка сжимается
    flexBasis: "740px",     // ширина колонки (≈620px текста при паддинге 60)
    maxWidth: "100%",
    minWidth: "0",          // КРИТ: иначе широкий код-блок (white-space:pre) через min-width:auto распирал колонку при скролле
    padding: "46px 60px 200px",
    boxSizing: "border-box",
  },
  ".cm-cursor": { borderLeftColor: "var(--ac)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": { backgroundColor: "var(--acs)" },
  ".cm-line": { lineHeight: "1.7" },
}, { dark: true });

// Задержка отправки doc в Swift: дебаунс debounce мс, но не позже maxWait от первого
// несохранённого ввода — иначе непрерывная печать бесконечно откладывала бы отправку,
// и весь набор жил бы только в webview (терялся при переключении файла/git-коммите).
export function docSendDelay(now, firstPendingAt, debounce = 250, maxWait = 1000) {
  if (!firstPendingAt) return debounce;
  return Math.max(0, Math.min(debounce, firstPendingAt + maxWait - now));
}

// Двойной пробел после слова → «. » (системное поведение macOS; в WKWebView само не работает).
// two — два символа перед курсором ДО ввода второго пробела: [словесный символ][пробел] → замена.
// После точки/пробела/пунктуации не срабатывает (третий пробел остаётся обычным пробелом).
export function autoPeriodBefore(two) {
  return typeof two === "string" && two.length === 2 && two[1] === " " &&
    /[\p{L}\p{N})\]»"']/u.test(two[0]);
}
