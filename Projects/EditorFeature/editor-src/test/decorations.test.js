// Интеграционные тесты builder'ов декораций на реальном EditorState + lezer-дереве (GFM).
// buildBlockDecorations(state) — чистый (state→RangeSet); buildDecorations(view) — фейковый view
// ({state, hasFocus, visibleRanges}) без реального EditorView. jsdom — для toDOM-проверок виджетов.
import { test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { ensureSyntaxTree } from "@codemirror/language";
import {
  buildBlockDecorations, buildDecorations, focusField, setFocus, setLivePreview,
  CalloutWidget, TableWidget, FrontmatterWidget, HrWidget, CheckboxWidget, BulletWidget, ImageWidget,
} from "../src/core.js";

// jsdom: виджеты создаются без DOM, но toDOM() требует document.
const dom = new JSDOM("<!DOCTYPE html><div id=editor></div>");
globalThis.document = dom.window.document;
globalThis.window = dom.window;
// Заглушка view для toDOM (attachReveal вешает listener, методы не вызываются синхронно).
const stubView = { posAtDOM: () => 0, dispatch: () => {}, focus: () => {} };

function mkState(doc, { focus = false, anchor = 0 } = {}) {
  let state = EditorState.create({ doc, extensions: [markdown({ base: markdownLanguage }), focusField] });
  ensureSyntaxTree(state, state.doc.length, 10000);   // форс-парс (как forceParsing в рантайме)
  if (focus) state = state.update({ effects: setFocus.of(true), selection: { anchor } }).state;
  else if (anchor) state = state.update({ selection: { anchor } }).state;
  return state;
}
function fakeView(state, hasFocus = false) {
  return { state, hasFocus, visibleRanges: [{ from: 0, to: state.doc.length }] };
}
// RangeSet → массив {from,to,kind,...}
function items(set) {
  const out = [];
  const it = set.iter();
  while (it.value) {
    const s = it.value.spec || {};
    let o;
    if (it.from === it.to) o = { kind: "line", class: s.class };
    else if (s.widget) o = { kind: "widget", widget: s.widget, block: !!s.block };
    else if (s.class) o = { kind: "mark", class: s.class, attrs: s.attributes };
    else o = { kind: "hide" };
    out.push({ from: it.from, to: it.to, ...o });
    it.next();
  }
  return out;
}
const widgets = (set, Cls) => items(set).filter((i) => i.kind === "widget" && i.widget instanceof Cls);

// ─────────────────────────── buildBlockDecorations ───────────────────────────

test("frontmatter → FrontmatterWidget [0,fStop]; открывающий --- НЕ HrWidget", () => {
  const st = mkState("---\ntitle: Тест\n---\n# Заголовок\n**жир**");
  const set = buildBlockDecorations(st);
  const fm = widgets(set, FrontmatterWidget);
  assert.equal(fm.length, 1, "одна frontmatter-панель");
  assert.equal(fm[0].from, 0);
  assert.equal(fm[0].to, st.doc.line(3).to);                 // до закрывающего ---
  assert.deepEqual(fm[0].widget.rows, [["title", "Тест"]]);
  assert.equal(widgets(set, HrWidget).length, 0, "--- frontmatter не рисуется как HR");
});

test("frontmatter с кареткой внутри (фокус) → раскрыт (нет виджета)", () => {
  const st = mkState("---\ntitle: T\n---\nтело", { focus: true, anchor: 1 });
  const set = buildBlockDecorations(st);
  assert.equal(widgets(set, FrontmatterWidget).length, 0);
});

test("callout → CalloutWidget block с типом/заголовком/телом", () => {
  const st = mkState("> [!note] Заголовок\n> первая\n> вторая");
  const w = widgets(buildBlockDecorations(st), CalloutWidget);
  assert.equal(w.length, 1);
  assert.equal(w[0].block, true);
  assert.equal(w[0].widget.type, "note");
  assert.equal(w[0].widget.title, "Заголовок");
  assert.deepEqual(w[0].widget.body, ["первая", "вторая"]);  // многострочное тело
});

test("callout: все типы + fold [!warning]-", () => {
  for (const t of ["note", "tip", "warning", "danger", "success", "question", "info"]) {
    const w = widgets(buildBlockDecorations(mkState(`> [!${t}] T`)), CalloutWidget);
    assert.equal(w.length, 1, `тип ${t}`);
    assert.equal(w[0].widget.type, t);
  }
  // fold-маркер не попадает в заголовок
  const folded = widgets(buildBlockDecorations(mkState("> [!warning]- Свёрнуто\n> тело")), CalloutWidget);
  assert.equal(folded[0].widget.type, "warning");
  assert.equal(folded[0].widget.title, "Свёрнуто");
});

test("table → TableWidget с header/rows/aligns + инлайн в ячейках", () => {
  const st = mkState("| A | B |\n| --- | :-: |\n| 1 | **2** |");
  const w = widgets(buildBlockDecorations(st), TableWidget);
  assert.equal(w.length, 1);
  assert.equal(w[0].block, true);
  assert.deepEqual(w[0].widget.header, ["A", "B"]);
  assert.deepEqual(w[0].widget.rows, [["1", "**2**"]]);
  assert.deepEqual(w[0].widget.aligns, ["left", "center"]);
  // инлайн рендерится в toDOM
  const td = w[0].widget.toDOM(stubView).querySelectorAll("td")[1];
  assert.equal(td.innerHTML, "<strong>2</strong>");
  assert.equal(td.style.textAlign, "center");
});

test("HR ---/***/___ в теле → HrWidget", () => {
  for (const hr of ["---", "***", "___"]) {
    const w = widgets(buildBlockDecorations(mkState(`текст\n\n${hr}\n\nещё`)), HrWidget);
    assert.equal(w.length, 1, `HR из ${hr}`);
    assert.equal(w[0].block, true);
  }
});

test("focus-gating: фокус+каретка в блоке → блок раскрыт, соседний рисуется", () => {
  const doc = "> [!note] Первый\n> a\n\n> [!tip] Второй\n> b";
  // нет фокуса → оба callout-а рисуются
  assert.equal(widgets(buildBlockDecorations(mkState(doc)), CalloutWidget).length, 2);
  // фокус + каретка в первом callout → первый раскрыт, второй остаётся
  const st = mkState(doc, { focus: true, anchor: 2 });
  const w = widgets(buildBlockDecorations(st), CalloutWidget);
  assert.equal(w.length, 1);
  assert.equal(w[0].widget.type, "tip");                     // остался второй
});

test("markdown-режим (setLivePreview false) → Decoration.none", () => {
  setLivePreview(false);
  try {
    assert.equal(buildBlockDecorations(mkState("> [!note] T")).size, 0);
    assert.equal(buildDecorations(fakeView(mkState("# H"))).size, 0);
  } finally {
    setLivePreview(true);                                    // восстановить для остальных тестов
  }
});

// CalloutWidget.toDOM — рендер коробки (jsdom).
test("CalloutWidget.toDOM: иконка + заголовок + тело", () => {
  const st = mkState("> [!tip] Совет\n> текст тела");
  const w = widgets(buildBlockDecorations(st), CalloutWidget)[0].widget;
  const el = w.toDOM(stubView);
  assert.ok(el.querySelector(".cm-callout.cm-cg-tip"), "класс группы tip");
  assert.match(el.querySelector(".cm-callout-title").textContent, /Совет/);
  assert.match(el.querySelector(".cm-callout-body").textContent, /текст тела/);
});

// ───────────────────────────── buildDecorations ──────────────────────────────

test("heading → ln-h1 + скрытие «# » когда не активна", () => {
  const its = items(buildDecorations(fakeView(mkState("# Заголовок"))));
  assert.ok(its.some((i) => i.kind === "line" && i.class === "ln-h1"));
  assert.ok(its.some((i) => i.kind === "hide" && i.from === 0 && i.to === 2), "спрятан «# »");
});

test("heading активна (фокус, каретка на строке) → «# » НЕ прячется", () => {
  const st = mkState("# Заголовок", { focus: true, anchor: 0 });
  const its = items(buildDecorations(fakeView(st, true)));
  assert.ok(its.some((i) => i.kind === "line" && i.class === "ln-h1"));
  assert.ok(!its.some((i) => i.kind === "hide"), "сырой # показан");
});

test("инлайн: bold→tok-strong, code→tok-code, strike→tok-strike, ссылка→data-href", () => {
  assert.ok(items(buildDecorations(fakeView(mkState("**жир**")))).some((i) => i.kind === "mark" && i.class === "tok-strong"));
  assert.ok(items(buildDecorations(fakeView(mkState("`код`")))).some((i) => i.kind === "mark" && i.class === "tok-code"));
  assert.ok(items(buildDecorations(fakeView(mkState("~~зч~~")))).some((i) => i.kind === "mark" && i.class === "tok-strike"));
  const link = items(buildDecorations(fakeView(mkState("[t](http://x)")))).find((i) => i.class === "tok-link");
  assert.equal(link.attrs["data-href"], "http://x");
});

test("РЕГРЕСС 2738: плагин НЕ порождает replace через перенос строки", () => {
  // ссылки/жир/код у концов строк + многострочный документ
  const st = mkState("# H с [ссылкой](http://x.com) в конце\nдалее **жир** тут\n`код` и всё");
  for (const i of items(buildDecorations(fakeView(st)))) {
    if (i.from === i.to) continue;                           // line-деко — не replace
    assert.equal(st.doc.lineAt(i.from).number, st.doc.lineAt(i.to).number,
      `replace [${i.from},${i.to}] не должен пересекать строку`);
  }
});

test("РЕГРЕСС fmEnd: скрытый frontmatter НЕ глотает весь документ", () => {
  // Баг: `a < fmEnd` пропускал корневой Document (a=0) → decos=0 ниже frontmatter.
  const st = mkState("---\ntitle: T\n---\n# Заголовок\n**жир**");
  const its = items(buildDecorations(fakeView(st)));
  assert.ok(its.some((i) => i.kind === "line" && i.class === "ln-h1"), "заголовок ниже fm декорируется");
  assert.ok(its.some((i) => i.kind === "mark" && i.class === "tok-strong"), "жир ниже fm декорируется");
});

test("чекбокс → CheckboxWidget (checked/unchecked), когда не активна", () => {
  const off = widgets(buildDecorations(fakeView(mkState("- [ ] задача"))), CheckboxWidget);
  assert.equal(off.length, 1);
  assert.equal(off[0].widget.checked, false);
  const on = widgets(buildDecorations(fakeView(mkState("- [x] готово"))), CheckboxWidget);
  assert.equal(on[0].widget.checked, true);
});

test("буллет «-» → BulletWidget; «1.» не трогаем", () => {
  assert.equal(widgets(buildDecorations(fakeView(mkState("- пункт"))), BulletWidget).length, 1);
  assert.equal(widgets(buildDecorations(fakeView(mkState("1. пункт"))), BulletWidget).length, 0);
});

test("плагин пропускает callout/table (ими владеет blockField)", () => {
  const callout = buildDecorations(fakeView(mkState("> [!note] T\n> тело")));
  assert.equal(widgets(callout, CalloutWidget).length, 0);
  const table = buildDecorations(fakeView(mkState("| A | B |\n| --- | --- |\n| 1 | 2 |")));
  assert.equal(widgets(table, TableWidget).length, 0);
});

test("forceParsing: callout/таблица рисуются с первого билда (без скролла)", () => {
  // длинный документ — узлы за пределами начального бюджета парсера должны дочитаться ensureSyntaxTree.
  const filler = Array.from({ length: 60 }, (_, i) => `Параграф номер ${i} с текстом для объёма.`).join("\n\n");
  const st = mkState(`${filler}\n\n> [!warning] Внизу\n> тело\n\n| X | Y |\n| --- | --- |\n| 1 | 2 |`);
  const set = buildBlockDecorations(st);
  assert.equal(widgets(set, CalloutWidget).length, 1, "callout внизу длинного дока");
  assert.equal(widgets(set, TableWidget).length, 1, "таблица внизу длинного дока");
});
