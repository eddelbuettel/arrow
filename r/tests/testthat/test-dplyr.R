# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

library(dplyr)
library(stringr)

tbl <- example_data
# Add some better string data
tbl$verses <- verses[[1]]
# c(" a ", "  b  ", "   c   ", ...) increasing padding
# nchar =   3  5  7  9 11 13 15 17 19 21
tbl$padded_strings <- stringr::str_pad(letters[1:10], width = 2*(1:10)+1, side = "both")

test_that("basic select/filter/collect", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5)

  expect_is(b2, "arrow_dplyr_query")
  t2 <- collect(b2)
  expect_equal(t2, tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")])
  # Test that the original object is not affected
  expect_identical(collect(batch), tbl)
})

test_that("dim() on query", {
  expect_dplyr_equal(
    input %>%
      filter(int > 5) %>%
      select(int, chr) %>%
      dim(),
    tbl
  )
})

test_that("Print method", {
  expect_output(
    record_batch(tbl) %>%
      filter(dbl > 2, chr == "d" | chr == "f") %>%
      select(chr, int, lgl) %>%
      filter(int < 5) %>%
      select(int, chr) %>%
      print(),
'RecordBatch (query)
int: int32
chr: string

* Filter: and(and(greater(dbl, 2), or(equal(chr, "d"), equal(chr, "f"))), less(int, 5))
See $.data for the source Arrow object',
  fixed = TRUE
  )
})

test_that("summarize", {
  expect_dplyr_equal(
    input %>%
      select(int, chr) %>%
      filter(int > 5) %>%
      summarize(min_int = min(int)),
    tbl
  )

  expect_dplyr_equal(
    input %>%
      select(int, chr) %>%
      filter(int > 5) %>%
      summarize(min_int = min(int) / 2),
    tbl
  )
})

test_that("group_by groupings are recorded", {
  expect_dplyr_equal(
    input %>%
      group_by(chr) %>%
      select(int, chr) %>%
      filter(int > 5) %>%
      summarize(min_int = min(int)),
    tbl
  )
  # Test that the original object is not affected
  expect_identical(collect(batch), tbl)
})

test_that("group_by doesn't yet support creating/renaming", {
  expect_error(
    record_batch(tbl) %>%
      group_by(chr, numbers = int),
    "Cannot create or rename columns in group_by on Arrow objects"
  )
})

test_that("ungroup", {
  expect_dplyr_equal(
    input %>%
      group_by(chr) %>%
      select(int, chr) %>%
      ungroup() %>%
      filter(int > 5) %>%
      summarize(min_int = min(int)),
    tbl
  )
  # Test that the original object is not affected
  expect_identical(collect(batch), tbl)
})

test_that("Empty select returns no columns", {
  expect_dplyr_equal(
    input %>% select() %>% collect(),
    tbl,
    skip_table = "Table with 0 cols doesn't know how many rows it should have"
  )
})
test_that("Empty select still includes the group_by columns", {
  expect_dplyr_equal(
    input %>% group_by(chr) %>% select() %>% collect(),
    tbl
  )
})

test_that("arrange", {
  expect_dplyr_equal(
    input %>%
      group_by(chr) %>%
      select(int, chr) %>%
      arrange(desc(int)) %>%
      collect(),
    tbl
  )
})

test_that("select/rename", {
  expect_dplyr_equal(
    input %>%
      select(string = chr, int) %>%
      collect(),
    tbl
  )
  expect_dplyr_equal(
    input %>%
      rename(string = chr) %>%
      collect(),
    tbl
  )
  expect_dplyr_equal(
    input %>%
      rename(strng = chr) %>%
      rename(other = strng) %>%
      collect(),
    tbl
  )
})

test_that("filtering with rename", {
  expect_dplyr_equal(
    input %>%
      filter(chr == "b") %>%
      select(string = chr, int) %>%
      collect(),
    tbl
  )
  expect_dplyr_equal(
    input %>%
      select(string = chr, int) %>%
      filter(string == "b") %>%
      collect(),
    tbl
  )
})

test_that("group_by then rename", {
  expect_dplyr_equal(
    input %>%
      group_by(chr) %>%
      select(string = chr, int) %>%
      collect(),
    tbl
  )
})

test_that("group_by with .drop", {
  expect_identical(
    Table$create(tbl) %>% 
      group_by(chr, .drop = TRUE) %>%
      group_vars(), 
    "chr"
  )
  expect_dplyr_equal(
    input %>%
      group_by(chr, .drop = TRUE) %>%
      collect(),
    tbl
  )
  expect_error(
    Table$create(tbl) %>% group_by(chr, .drop = FALSE),
    "not supported"
  )
})

test_that("pull", {
  expect_dplyr_equal(
    input %>% pull(),
    tbl
  )
  expect_dplyr_equal(
    input %>% pull(1),
    tbl
  )
  expect_dplyr_equal(
    input %>% pull(chr),
    tbl
  )
  expect_dplyr_equal(
    input %>%
      filter(int > 4) %>%
      rename(strng = chr) %>%
      pull(strng),
    tbl
  )
})

test_that("collect(as_data_frame=FALSE)", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    collect(as_data_frame = FALSE)

  expect_is(b2, "RecordBatch")
  expected <- tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")]
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    collect(as_data_frame = FALSE)
  expect_is(b3, "RecordBatch")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    collect(as_data_frame = FALSE)
  expect_is(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
    )
})

test_that("head", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    head(2)

  expect_is(b2, "RecordBatch")
  expected <- tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")][1:2, ]
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    head(2)
  expect_is(b3, "RecordBatch")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    head(2)
  expect_is(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
    )
})

test_that("tail", {
  batch <- record_batch(tbl)

  b2 <- batch %>%
    select(int, chr) %>%
    filter(int > 5) %>%
    tail(2)

  expect_is(b2, "RecordBatch")
  expected <- tail(tbl[tbl$int > 5 & !is.na(tbl$int), c("int", "chr")], 2)
  expect_equal(as.data.frame(b2), expected)

  b3 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    tail(2)
  expect_is(b3, "RecordBatch")
  expect_equal(as.data.frame(b3), set_names(expected, c("int", "strng")))

  b4 <- batch %>%
    select(int, strng = chr) %>%
    filter(int > 5) %>%
    group_by(int) %>%
    tail(2)
  expect_is(b4, "arrow_dplyr_query")
  expect_equal(
    as.data.frame(b4),
    expected %>%
      rename(strng = chr) %>%
      group_by(int)
    )
})
