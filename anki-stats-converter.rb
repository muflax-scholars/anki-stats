#!/usr/bin/env ruby
# coding: utf-8
# Copyright muflax <mail@muflax.com>, 2012
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

require "sqlite3"

old_decks = Dir["anki-old-revlog/*.anki"]
new_db = SQLite3::Database.new "spoiler/anki/muflax/collection.anki2"

old_decks.each do |deck|
  puts "porting #{deck}..."

  old_db = SQLite3::Database.new deck
  rows = old_db.execute("select cast(time*1000 as int), cardId, 0, ease, cast(nextInterval as int), cast(lastInterval as int),
cast(nextFactor*1000 as int), cast(min(thinkingTime, 60)*1000 as int), yesCount from reviewHistory")
  puts "found #{rows.size} reviews..."

  new_db.transaction do |db|
    rows.each_with_index do |row, i|
      row[1] = 0 # reset card id
      row[3] = 1 if row[3] == 0
      # new type
      newInt = row[4]
      oldInt = row[5]
      yesCnt = row[8]
      yesCnt -= 1 if row[3] > 1
      if oldInt < 1
        # new or failed
        if yesCnt != 0
          # type=relrn
          row[8] = 2
        else
          # type=lrn
          row[8] = 0
        end
      else
        # type=rev
        row[8] = 1
      end

      # insert into new db
      puts "insert row #{i}..."
      db.execute("insert or ignore into revlog values (?,?,?,?,?,?,?,?,?)", row)
    end
  end
end
