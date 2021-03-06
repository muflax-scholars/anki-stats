#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Copyright muflax <mail@muflax.com>, 2013
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

require "muflax"
require "sqlite3"
require "json"

opts = Trollop::options do
  opt :database, "which database to use", :type => :string, :default => "~/anki/muflax/collection.anki2"
end

AnkiFile = File.expand_path(opts[:database])

puts "opening #{AnkiFile}..."
anki_db = SQLite3::Database.new(AnkiFile)

# times needed for due calculations
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

TimeForCard   = vivaHash 0
AnswersByEase = vivaHash []
RetentionRate = {}

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

# use the average of the retention rates, but cap at 95%
AnswersByEase.each do |ease, answers|
  RetentionRate[ease] = [answers.average, 0.95].min
end

Card = Struct.new :id, :deck_id, :type, :queue, :due, :interval, :factor, :time do
  def ease
    factor / 100
  end

  def deck
    Decks[deck_id.to_s]["name"]
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

  def due? day=Today
    due_date <= day
  end

  def remember_prob day=Today
    decay_rate = Math.log(retention_rate) / interval

    prob = Math.exp(decay_rate * (day - review_date))

    prob
  end

  def time
    # in minutes
    TimeForCard[id] / 60
  end

  def stage
    Math.log(interval, ease / 10.0).round
  end
end
all_cards = anki_db.execute("select id, did, type, queue, due, ivl, factor from cards").map{|c| Card.new(*c)}
puts "#{all_cards.size} cards loaded."

# read decks
Decks = JSON.load(anki_db.get_first_row("select decks from col").first)

cards_by_deck = all_cards.group_by(&:deck)
puts "#{cards_by_deck.size} decks in use."
puts

Intervals = [
  [1, "today"],
  [7, "for a week"],
  [30, "for a month"],
  [365, "for a year"],
]

cards_by_deck.sort.each do |deck, cards|
  # stats
  new_cards      = 0
  learning_cards = 0
  review_cards   = vivaHash 0
  time_invested  = 0
  time_wasted    = vivaHash 0
  forgotten      = 0

  puts "#{deck}:"
  cards.each do |card|

    time_invested += card.time

    case card.queue
    when 0 # new
      new_cards += 1
    when 1 # learning
      learning_cards += 1
    when 2, -2, -3 # review queue or buried
      forgotten += 1 if card.remember_prob(Today) < 0.5

      (Intervals + [0]).each do |i, _|
        review_cards[i] += 1 if card.due? Today + i

        if card.due? Today + i
          prob_diff = card.remember_prob(card.due_date) - card.remember_prob(Today + i)

          time_wasted[i]     += card.time  * prob_diff
        end
      end
    when -1 # suspended
      # don't care
    end
  end

  # show statistics
  effort_wasted = time_wasted[0].to_f / time_invested.to_f

  puts "#{new_cards} unreviewed, #{learning_cards} in learning queue, #{review_cards[0]} to review, #{review_cards[0] + learning_cards + new_cards} cards total."
  puts "%.1f min invested, %.1f min wasted, %.1f%% of effort lost." % [
    time_invested,
    time_wasted[0],
    effort_wasted * 100,
  ]
  puts "#{forgotten} (%.1f%%) cards likely forgotten." % ((forgotten.to_f / review_cards[0]) * 100)
  puts

  Intervals.each do |interval, name|
    puts "%7.1f min (%+7.1f min), %7.1f%% (%+6.1f%%) of effort wasted if you don't study #{name}." % [
      time_wasted[interval],
      time_wasted[interval] - time_wasted[0],
      (time_wasted[interval].to_f / time_invested.to_f) * 100,
      ((time_wasted[interval].to_f / time_invested.to_f) - effort_wasted) * 100,
      ]
  end

  puts
end
