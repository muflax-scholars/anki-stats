#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Copyright muflax <mail@muflax.com>, 2013
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

require "muflax"
require "sqlite3"

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
cards = anki_db.execute("select id, type, queue, due, ivl, factor from cards").map{|c| Card.new(*c)}
puts "#{cards.size} cards loaded."

# stats
new_cards      = 0
learning_cards = 0
review_cards   = vivaHash 0
time_invested  = 0
time_wasted    = vivaHash 0
extra_reviews  = vivaHash 0

cards.each do |card|
  time_invested += card.time

  case card.queue
  when 0 # new
    new_cards += 1
  when 1 # learning
    learning_cards += 1
  when 2, -2, -3 # review queue or buried
    [0, 1, 7, 30, 365, 365*10].each do |i|
      review_cards[i] += 1 if card.due? Today + i

      if card.due? Today + i
        prob_diff = card.remember_prob(card.due_date) - card.remember_prob(Today + i)

        time_wasted[i]     += card.time  * prob_diff
        extra_reviews[i]   += card.stage * prob_diff
      end
    end
  when -1 # suspended
    # don't care
  end

  puts
end

# show statistics
puts "#{new_cards} unreviewed new cards."
puts "#{learning_cards} cards in learning queue (counting as unlearned)."
puts "#{review_cards[0]} cards to review."
puts "#{review_cards[0] + learning_cards + new_cards} cards total to do."

puts
puts "%.1f min already invested." % time_invested

puts
puts " %6.1f           min already wasted."                        %  time_wasted[0]
puts "%7.1f (%+7.1f) min wasted if you don't study today."         % [time_wasted[1],
                                                                      time_wasted[1]    - time_wasted[0]]
puts "%7.1f (%+7.1f) min wasted if you don't study for a week."    % [time_wasted[7],
                                                                      time_wasted[7]    - time_wasted[0]]
puts "%7.1f (%+7.1f) min wasted if you don't study for a month."   % [time_wasted[30],
                                                                      time_wasted[30]   - time_wasted[0]]
puts "%7.1f (%+7.1f) min wasted if you don't study for a year."    % [time_wasted[365],
                                                                      time_wasted[365]  - time_wasted[0]]
puts "%7.1f (%+7.1f) min wasted if you don't study for ten years." % [time_wasted[3650],
                                                                      time_wasted[3650] - time_wasted[0]]

time_wasted.each do |i, _|
  next if i == 0
  time_wasted[i] -= time_wasted[0]
end

puts
puts "%7.1f min (%7.1f sec) cheaper than tomorrow."     % [time_wasted[1] / review_cards[1],
                                                           time_wasted[1]    * 60 / review_cards[1]]
puts "%7.1f min (%7.1f sec) cheaper than in a week."    % [time_wasted[7] / review_cards[7],
                                                           time_wasted[7]    * 60 / review_cards[7]]
puts "%7.1f min (%7.1f sec) cheaper than in a month."   % [time_wasted[30] / review_cards[30],
                                                           time_wasted[30]   * 60 / review_cards[30]]
puts "%7.1f min (%7.1f sec) cheaper than in a year."    % [time_wasted[365] / review_cards[365],
                                                           time_wasted[365]  * 60 / review_cards[365]]
puts "%7.1f min (%7.1f sec) cheaper than in ten years." % [time_wasted[3650] / review_cards[3650],
                                                           time_wasted[3650] * 60 / review_cards[3650]]

puts
puts " %6.1f           extra reviews already added."                   %  extra_reviews[0]
puts "%+7.1f (%+7.1f) extra reviews if you don't study today."         % [extra_reviews[1],
                                                                          extra_reviews[1]    - extra_reviews[0]]
puts "%+7.1f (%+7.1f) extra reviews if you don't study for a week."    % [extra_reviews[7],
                                                                          extra_reviews[7]    - extra_reviews[0]]
puts "%+7.1f (%+7.1f) extra reviews if you don't study for a month."   % [extra_reviews[30],
                                                                          extra_reviews[30]   - extra_reviews[0]]
puts "%+7.1f (%+7.1f) extra reviews if you don't study for a year."    % [extra_reviews[365],
                                                                          extra_reviews[365]  - extra_reviews[0]]
puts "%+7.1f (%+7.1f) extra reviews if you don't study for ten years." % [extra_reviews[3650],
                                                                          extra_reviews[3650] - extra_reviews[0]]
