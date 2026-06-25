// Юнит-тесты чистых функций core.js (без DOM). Раннер: node --test.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  escapeHtml, renderInline, parseAligns, bodyStartOffset,
  calloutIcon, cap, renderCalloutBody, CALLOUT_ICON, CALLOUT_GROUP,
} from "../src/core.js";

test("escapeHtml экранирует & < >", () => {
  assert.equal(escapeHtml("a<b>&c"), "a&lt;b&gt;&amp;c");
  assert.equal(escapeHtml("<script>"), "&lt;script&gt;");
  assert.equal(escapeHtml("без спецсимволов"), "без спецсимволов");
  // & экранируется ПЕРВЫМ — нет двойного экранирования уже-сущностей
  assert.equal(escapeHtml("&lt;"), "&amp;lt;");
});

test("renderInline: жирный/курсив/код/зачёркнутый", () => {
  assert.equal(renderInline("**bold**"), "<strong>bold</strong>");
  assert.equal(renderInline("__bold__"), "<strong>bold</strong>");
  assert.equal(renderInline("*em*"), "<em>em</em>");
  assert.equal(renderInline("`code`"), '<code class="tok-code">code</code>');
  assert.equal(renderInline("~~strike~~"), "<del>strike</del>");
});

test("renderInline: кириллица внутри маркеров", () => {
  assert.equal(renderInline("**жирный**"), "<strong>жирный</strong>");
  assert.equal(renderInline("*курсив*"), "<em>курсив</em>");
});

test("renderInline: ссылки обычные и с пробелами в <>", () => {
  assert.equal(renderInline("[t](http://x.com)"),
    '<a class="tok-link" data-href="http://x.com">t</a>');
  // [t](<url с пробелами>) → после escapeHtml путь в &lt;...&gt;, href сохраняет пробелы
  assert.equal(renderInline("[Заметка](<Папка/Моя заметка.md>)"),
    '<a class="tok-link" data-href="Папка/Моя заметка.md">Заметка</a>');
});

test("renderInline: экранирует html в тексте и в коде", () => {
  assert.equal(renderInline("<div>"), "&lt;div&gt;");
  // содержимое кода уже экранировано (escapeHtml идёт первым)
  assert.equal(renderInline("`<b>`"), '<code class="tok-code">&lt;b&gt;</code>');
});

test("parseAligns: :--/:-:/--: и крайние пайпы", () => {
  assert.deepEqual(parseAligns("| :-- | :-: | --: |"), ["left", "center", "right"]);
  assert.deepEqual(parseAligns("| --- | --- |"), ["left", "left"]);
  assert.deepEqual(parseAligns(":---:|---:"), ["center", "right"]);
});

test("bodyStartOffset: нет frontmatter → 0", () => {
  assert.equal(bodyStartOffset(""), 0);
  assert.equal(bodyStartOffset("# Заголовок\nтекст"), 0);
  assert.equal(bodyStartOffset("обычный текст"), 0);
});

test("bodyStartOffset: --- … --- → начало тела", () => {
  const doc = "---\nkey: v\n---\nbody";
  // "body" начинается на индексе 15 (3+1 + 6+1 + 3+1)
  assert.equal(bodyStartOffset(doc), 15);
  assert.equal(doc.slice(bodyStartOffset(doc)), "body");
});

test("bodyStartOffset: незакрытый frontmatter → 0", () => {
  assert.equal(bodyStartOffset("---\nkey: v\nbody"), 0);
  assert.equal(bodyStartOffset("---"), 0);
});

test("calloutIcon/cap: маппинг и фолбэки", () => {
  assert.equal(calloutIcon("note"), CALLOUT_ICON.note);
  assert.equal(calloutIcon("warning"), CALLOUT_ICON.warning);
  assert.equal(calloutIcon("несуществует"), "📌");
  assert.equal(cap("note"), "Note");
  assert.equal(cap("warning"), "Warning");
  assert.equal(cap(""), "");
});

test("CALLOUT_ICON/GROUP: все типы покрыты, unknown→note", () => {
  // У каждого типа из ICON есть группа; иконка — непустая строка.
  for (const t of Object.keys(CALLOUT_ICON)) {
    assert.ok(calloutIcon(t).length > 0, `иконка для ${t}`);
    assert.ok(typeof CALLOUT_GROUP[t] === "string", `группа для ${t}`);
  }
  // Ключевые группировки (как в Obsidian).
  assert.equal(CALLOUT_GROUP.tip, "tip");
  assert.equal(CALLOUT_GROUP.bug, "danger");
  assert.equal(CALLOUT_GROUP.success, "success");
  assert.equal(CALLOUT_GROUP.error, "danger");
  // unknown → фолбэк "note" (логика виджета: CALLOUT_GROUP[t] || "note")
  assert.equal(CALLOUT_GROUP["неизвестно"] || "note", "note");
});

test("renderCalloutBody: буллеты → <ul>, текст → <div>, пусто → spacer", () => {
  assert.equal(renderCalloutBody(["- a", "- b"]),
    "<ul class='cm-callout-ul'><li>a</li><li>b</li></ul>");
  assert.equal(renderCalloutBody(["просто текст"]), "<div>просто текст</div>");
  assert.equal(renderCalloutBody([""]), "<div class='cm-callout-sp'></div>");
  assert.equal(renderCalloutBody(["**жир**"]), "<div><strong>жир</strong></div>");
  // список закрывается перед обычной строкой
  assert.equal(renderCalloutBody(["- a", "txt"]),
    "<ul class='cm-callout-ul'><li>a</li></ul><div>txt</div>");
});
