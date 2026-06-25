// Юнит-тесты сборки markdown-ссылки (buildLink) + что linkMarkdown делегирует в неё.
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildLink, linkMarkdown } from "../src/core.js";

test("buildLink: метка + путь", () => {
  assert.equal(buildLink("Текст", "Папка/Файл.md"), "[Текст](Папка/Файл.md)");
});

test("buildLink: пустая метка → «ссылка»", () => {
  assert.equal(buildLink("", "p.md"), "[ссылка](p.md)");
  assert.equal(buildLink("   ", "p.md"), "[ссылка](p.md)");
});

test("buildLink: срез скобок [] и обрезка пробелов", () => {
  assert.equal(buildLink("[br]ackets", "p"), "[brackets](p)");
  assert.equal(buildLink("  отступ  ", "p"), "[отступ](p)");
});

test("buildLink: пробелы в пути → <...>", () => {
  assert.equal(buildLink("t", "Папка/Моя заметка.md"), "[t](<Папка/Моя заметка.md>)");
  assert.equal(buildLink("t", "no-spaces.md"), "[t](no-spaces.md)");
});

test("linkMarkdown делегирует в buildLink (поведение сохранено)", () => {
  assert.equal(linkMarkdown("Выделенный", "Заголовок", "p.md"), "[Выделенный](p.md)");
  assert.equal(linkMarkdown("", "Заголовок", "p.md"), "[Заголовок](p.md)");
  assert.equal(linkMarkdown("", "", "p.md"), "[ссылка](p.md)");
});
