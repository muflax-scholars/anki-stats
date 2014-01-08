# -*- coding: utf-8 -*-
# by: muflax <mail@muflax.com>, 2014

# Search for cards based on estimated probability of remembering them.
#
# Use 'prob' to search for cards based on how likely it is you still remember them, using percent.
#
# Examples:
#   'prob:80'  finds cards that you remember at p >= 80%.
#   'prob:<50' finds cards that you remember at p < 50%.

from aqt import mw
from anki.hooks import addHook
import datetime, time
import math, re

def findProbability((var, args)):
    query = var

    # extract argument
    m = re.match("^(<=|>=|!=|=|<|>)?(\d+)$", query)
    if not m:
        # invalid input, ignore it
        return
    comparison, percentage = m.groups()

    if not comparison:
        comparison = ">="

    # is percentage valid?
    try:
        probability = float(percentage) / 100.0
    except ValueError:
        return

    # sqlite doesn't understand logarithms, so we pre-calculate them
    log_probability    = -math.log(probability)
    log_retention_rate = -math.log(0.95)
    start_day          = mw.col.crt / 86400
    today              = int(time.mktime(datetime.datetime.today().timetuple())) / 86400
    # from card: due, ivl

    # formula: p = e * [(today - (start_day + due - ivl)) * (ln(retention_rate)/ivl)]

    # query
    q = []

    # only valid for review
    q.append("(c.queue == 2)")

    q.append("(%s %s ( (%s - (%s + c.due - c.ivl)) * (%s / c.ivl) ) )" % (
        log_probability,
        comparison,
        today,
        start_day,
        log_retention_rate))

    return " and ".join(q)

def addFindProbability(search):
    search["prob"]        = findProbability
    search["probability"] = findProbability

addHook("search", addFindProbability)
