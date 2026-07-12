import { test } from "node:test";
import assert from "node:assert/strict";
import { autoPeriodBefore } from "../src/core.js";

// autoPeriodBefore(two): two = два символа перед курсором в момент ввода ВТОРОГО пробела.
// [словесный символ][пробел] → заменяем предыдущий пробел на ". " (системное поведение macOS).

test("буква/цифра/кириллица + пробел → точка", () => {
  assert.equal(autoPeriodBefore("b "), true);
  assert.equal(autoPeriodBefore("я "), true);
  assert.equal(autoPeriodBefore("5 "), true);
});

test("закрывающие скобки/кавычки + пробел → точка", () => {
  assert.equal(autoPeriodBefore(") "), true);
  assert.equal(autoPeriodBefore("] "), true);
  assert.equal(autoPeriodBefore("» "), true);
  assert.equal(autoPeriodBefore('" '), true);
});

test("после точки/пунктуации/пробела — НЕ срабатывает", () => {
  assert.equal(autoPeriodBefore(". "), false);
  assert.equal(autoPeriodBefore(", "), false);
  assert.equal(autoPeriodBefore("  "), false);
  assert.equal(autoPeriodBefore("- "), false);
});

test("без предшествующего пробела/переноса — НЕ срабатывает", () => {
  assert.equal(autoPeriodBefore("ab"), false);
  assert.equal(autoPeriodBefore("a\n"), false);
  assert.equal(autoPeriodBefore("\n "), false);
});

test("мусорный вход — false", () => {
  assert.equal(autoPeriodBefore(""), false);
  assert.equal(autoPeriodBefore(" "), false);
  assert.equal(autoPeriodBefore(null), false);
  assert.equal(autoPeriodBefore(undefined), false);
});
