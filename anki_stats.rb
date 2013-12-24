#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Copyright muflax <mail@muflax.com>, 2013
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

require "muflax"
require "sqlite3"

RetentionRates = vivaHash 0.90
AnkiFile = "~/anki/muflax/collection.anki2"

def decay_prob days_since_last_review, last_interval, retention_rate
  decay_rate = Math.log(retention_rate) / last_interval

  prob = Math.exp(decay_rate * days_since_last_review)

  prob
end

puts "opening #{AnkiFile}..."
anki_db = SQLite3::Database.new(File.expand_path(AnkiFile))

# due calculation:
#
# queue types: 0=new/cram, 1=lrn, 2=rev, 3=day lrn, -1=suspended, -2=buried
# revlog types: 0=lrn, 1=rev, 2=relrn, 3=cram
# positive revlog intervals are in days (rev), negative in seconds (lrn)
#
# Type: 0=new, 1=learning, 2=due
# Queue: same as above, and:
#        -1=suspended, -2=user buried, -3=sched buried
# Due is used differently for different queues.
# - new queue: note id or random int
# - rev queue: integer day
# - lrn queue: integer timestamp

stats = anki_db.execute("select id, cid, ease, factor, ivl, type from revlog")
puts "#{stats.size} stats loaded."

stats.each do |id, cardId, ease, factor, ivl, type|
end

cards = anki_db.execute("select id, type, queue, due, ivl, factor from cards")
puts "#{cards.size} cards loaded."

# cards without a history yet
new_cards      = 0
learning_cards = 0

cards.each do |id, type, queue, due, ivl, factor|
  case queue
  when 0 # new
    new_cards += 1
  when 1 # learning
    learning_cards += 1
  when 2, -2, -3 # review queue or buried
  when -1 # suspended
    # don't care
  else
    # shouldn't happen
  end
end

puts "#{new_cards} unreviewed new cards."
puts "#{learning_cards} cards in learning queue (counting as unlearned)."
