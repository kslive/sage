// Юнит-тесты toggle-форматирования и сборки markdown-ссылки. Раннер: node --test.
import { test } from "node:test";
import assert from "node:assert/strict";
import { decideToggle, linkMarkdown } from "../src/core.js";

test("decideToggle: добавить когда маркеров нет", () => {
  assert.equal(decideToggle("bold", "", "", "**", "**"), "wrap");
  assert.equal(decideToggle("", "", "", "**", "**"), "wrap");
});

test("decideToggle: снять когда маркеры ВНУТРИ выделения", () => {
  assert.equal(decideToggle("**bold**", "", "", "**", "**"), "inside");
  assert.equal(decideToggle("*em*", "", "", "*", "*"), "inside");
  assert.equal(decideToggle("~~s~~", "", "", "~~", "~~"), "inside");
});

test("decideToggle: снять когда маркеры ВОКРУГ выделения", () => {
  assert.equal(decideToggle("bold", "**", "**", "**", "**"), "around");
  assert.equal(decideToggle("em", "*", "*", "*", "*"), "around");
});

test("decideToggle: одиночный маркер не считается обёрткой → wrap", () => {
  assert.equal(decideToggle("*", "", "", "*", "*"), "wrap");
  assert.equal(decideToggle("**", "", "", "**", "**"), "wrap");
});

test("decideToggle: вложенное — снятие внутреннего имеет приоритет", () => {
  // выделено "**bold**", а вокруг тоже ** → сначала снимаем внутренние (inside)
  assert.equal(decideToggle("**bold**", "**", "**", "**", "**"), "inside");
});

test("linkMarkdown: выделение становится лейблом", () => {
  assert.equal(linkMarkdown("Выделенный текст", "Заголовок", "Папка/Файл.md"),
    "[Выделенный текст](Папка/Файл.md)");
});

test("linkMarkdown: без выделения — title, иначе «ссылка»", () => {
  assert.equal(linkMarkdown("", "Заголовок", "p.md"), "[Заголовок](p.md)");
  assert.equal(linkMarkdown("", "", "p.md"), "[ссылка](p.md)");
});

test("linkMarkdown: пробелы в пути → <...>", () => {
  assert.equal(linkMarkdown("", "t", "Папка/Моя заметка.md"),
    "[t](<Папка/Моя заметка.md>)");
  assert.equal(linkMarkdown("", "t", "no-spaces.md"), "[t](no-spaces.md)");
});

test("linkMarkdown: срез скобок [] и обрезка пробелов в лейбле", () => {
  assert.equal(linkMarkdown("[br]ackets", "t", "p"), "[brackets](p)");
  assert.equal(linkMarkdown("  отступ  ", "t", "p"), "[отступ](p)");
});
