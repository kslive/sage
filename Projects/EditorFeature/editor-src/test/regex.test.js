// Юнит-тесты регэкспов core.js (детекторы блоков/строк, slash-триггер). Раннер: node --test.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CALLOUT_RE, CALLOUT_FULL_RE, TASK_RE, BULLET_RE,
  FRONTMATTER_RE, HEADING_PREFIX_RE, FM_KV_RE, SLASH_RE, HEADING,
} from "../src/core.js";

test("CALLOUT_RE: детект callout, регистр и отступ, не-callout", () => {
  assert.match("> [!note]", CALLOUT_RE);
  assert.equal(CALLOUT_RE.exec("> [!note]")[1], "note");
  assert.match("> [!WARNING] заголовок", CALLOUT_RE);        // регистронезависимо
  assert.match("  > [!tip]", CALLOUT_RE);                    // ведущий отступ
  assert.doesNotMatch("> обычная цитата", CALLOUT_RE);
  assert.doesNotMatch("[!note] без цитаты", CALLOUT_RE);
});

test("CALLOUT_FULL_RE: тип + fold +/- + заголовок", () => {
  let m = CALLOUT_FULL_RE.exec("> [!note]- Свёрнуто");
  assert.equal(m[1], "note");
  assert.equal(m[2], "Свёрнуто");                            // fold-маркер не попал в заголовок
  m = CALLOUT_FULL_RE.exec("> [!tip]+ Заголовок");
  assert.equal(m[1], "tip");
  assert.equal(m[2], "Заголовок");
  m = CALLOUT_FULL_RE.exec("> [!info] Текст");
  assert.equal(m[2], "Текст");
  m = CALLOUT_FULL_RE.exec("> [!note]");
  assert.equal(m[2], "");                                    // пустой заголовок
});

test("TASK_RE: чекбоксы [ ]/[x]/[X], отступ, маркеры -*+", () => {
  assert.equal(TASK_RE.exec("- [ ] задача")[3], " ");
  assert.equal(TASK_RE.exec("- [x] готово")[3], "x");
  assert.equal(TASK_RE.exec("- [X] готово")[3], "X");
  const nested = TASK_RE.exec("  * [ ] вложенная");
  assert.equal(nested[1], "  ");                             // отступ
  assert.equal(nested[2], "*");                              // маркер
  assert.doesNotMatch("- обычный пункт", TASK_RE);
  assert.doesNotMatch("- [ ]нет пробела", TASK_RE);          // нужен \s после ]
});

test("BULLET_RE: буллеты -*+ vs нумерованный/текст", () => {
  assert.match("- пункт", BULLET_RE);
  assert.match("* пункт", BULLET_RE);
  assert.match("+ пункт", BULLET_RE);
  assert.match("   - вложенный", BULLET_RE);
  assert.doesNotMatch("1. нумерованный", BULLET_RE);
  assert.doesNotMatch("обычный текст", BULLET_RE);
});

test("FRONTMATTER_RE: --- с хвостовыми пробелами, но не ----", () => {
  assert.match("---", FRONTMATTER_RE);
  assert.match("---   ", FRONTMATTER_RE);                    // хвостовые пробелы
  assert.doesNotMatch("----", FRONTMATTER_RE);               // 4 дефиса — не fm
  assert.doesNotMatch("-- ", FRONTMATTER_RE);
  assert.doesNotMatch("--- текст", FRONTMATTER_RE);
});

test("HEADING_PREFIX_RE: # … ###### + пробел, но не 7 и не #слитно", () => {
  assert.match("# H", HEADING_PREFIX_RE);
  assert.match("###### H", HEADING_PREFIX_RE);
  assert.doesNotMatch("####### H", HEADING_PREFIX_RE);       // 7 уровней — не заголовок
  assert.doesNotMatch("#нет-пробела", HEADING_PREFIX_RE);
  assert.doesNotMatch("текст", HEADING_PREFIX_RE);
});

test("HEADING: маппинг узлов ATXHeading1..6 → ln-h*", () => {
  assert.equal(HEADING.ATXHeading1, "ln-h1");
  assert.equal(HEADING.ATXHeading2, "ln-h2");
  assert.equal(HEADING.ATXHeading3, "ln-h3");
  assert.equal(HEADING.ATXHeading4, "ln-h4");
  assert.equal(HEADING.ATXHeading5, "ln-h4");
  assert.equal(HEADING.ATXHeading6, "ln-h4");
});

test("FM_KV_RE: key: value, точки в ключе, пустое значение", () => {
  let m = FM_KV_RE.exec("key: value");
  assert.equal(m[1], "key");
  assert.equal(m[2], "value");
  m = FM_KV_RE.exec("title: Моя заметка");
  assert.equal(m[2], "Моя заметка");
  m = FM_KV_RE.exec("created.at: 2026");
  assert.equal(m[1], "created.at");                          // точки в ключе
  m = FM_KV_RE.exec("tags:");
  assert.equal(m[2], "");                                    // пустое значение
  assert.equal(FM_KV_RE.exec("без двоеточия"), null);
});

// Решение slash-триггера = SLASH_RE + guard на prevCh (как в checkSlash, без view).
function slashTriggers(before) {
  const m = SLASH_RE.exec(before);
  if (!m) return false;
  const slashIdx = before.length - m[0].length;
  const prevCh = slashIdx > 0 ? before[slashIdx - 1] : "";
  return prevCh !== ":" && prevCh !== "/";
}

test("SLASH-триггер: после буквы — да; после :// и // — нет", () => {
  assert.equal(slashTriggers("/"), true);
  assert.equal(slashTriggers("слово/"), true);              // сразу после буквы слова
  assert.equal(slashTriggers("/cmd"), true);
  assert.equal(slashTriggers("http://"), false);            // URL — не триггерим
  assert.equal(slashTriggers("see http://x"), false);
  assert.equal(slashTriggers("a//"), false);                // //
  assert.equal(slashTriggers("без слэша"), false);
});
