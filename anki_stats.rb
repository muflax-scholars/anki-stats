#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Copyright muflax <mail@muflax.com>, 2013
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

require "muflax"
require "sqlite3"

AnswersByEase = vivaHash []
RetentionRate = vivaHash 0.90
AnkiFile = "~/anki/muflax/collection.anki2"

puts "opening #{AnkiFile}..."
anki_db = SQLite3::Database.new(File.expand_path(AnkiFile))

DeckCreation = anki_db.get_first_row("select crt from col").first
StartDate    = Date.strptime(DeckCreation.to_s, "%s")
Today        = Date.today
puts "deck started on #{StartDate}"

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

TimeForCard = vivaHash 0

stats = anki_db.execute("select id, cid, ease, factor, ivl, type, time from revlog")
puts "#{stats.size} stats loaded."

stats.each do |id, cardId, answer, factor, interval, type, time|
  # use the factor (within 10%) as the ease
  ease = factor / 100

  TimeForCard[cardId] += time / 1000.0

  # only consider proper reviews
  next unless type == 1 and interval > 0

  # 1 -> wrong, 2..4 -> correct
  AnswersByEase[ease] << (answer == 1 ? 0 : 1)
end

# use the average of the retention rates, but cap at 99%
AnswersByEase.each do |ease, answers|
  RetentionRate[ease] = [answers.average, 0.99].min
end

Card = Struct.new :id, :type, :queue, :due, :interval, :factor, :time do
  def ease
    factor / 100
  end

  def retention_rate
    RetentionRate[ease]
  end

  def due_date
    StartDate + due
  end

  def review_date
    due_date - interval
  end

  def due? day=0
    due_date <= Today+day
  end

  def remember_prob day=0
    decay_rate = Math.log(retention_rate) / interval

    prob = Math.exp(decay_rate * ((Today - review_date) + day))

    prob
  end

  def time
    TimeForCard[id]
  end
end
cards = anki_db.execute("select id, type, queue, due, ivl, factor from cards").map{|c| Card.new(*c)}
puts "#{cards.size} cards loaded."

# cards without a history yet
new_cards      = 0
learning_cards = 0

work_wasted = vivaHash 0

cards.each do |card|
  case card.queue
  when 0 # new
    new_cards += 1
  when 1 # learning
    learning_cards += 1
  when 2, -2, -3 # review queue or buried
    # ap retention_rate


    # ap(id: card.id,
    #    r: card.review_date,
    #    i: card.interval,
    #    due: card.due_date,
    #    p: card.remember_prob,
    #    pt: card.remember_prob(1),
    #    pw: card.remember_prob(7),
    #    pm: card.remember_prob(30),
    #   ) if card.due?

    if card.due?
      [1, 7, 30, 365].each do |i|
        work_wasted[i] += card.time * (card.remember_prob - card.remember_prob(i))
      end
    end
  when -1 # suspended
    # don't care
  end
end

puts
puts "#{new_cards} unreviewed new cards."
puts "#{learning_cards} cards in learning queue (counting as unlearned)."

puts
puts "%0.2f minutes of work wasted if you don't study today."       % (work_wasted[1]   / 60.0)
puts "%0.2f minutes of work wasted if you don't study for a week."  % (work_wasted[7]   / 60.0)
puts "%0.2f minutes of work wasted if you don't study for a month." % (work_wasted[30]  / 60.0)
puts "%0.2f minutes of work wasted if you don't study for a year."  % (work_wasted[365] / 60.0)
