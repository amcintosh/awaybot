#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'
require 'chronic_duration'
require 'slack-notifier'
require 'open-uri'
require 'icalendar'
require 'yaml'
require 'date'
require 'pp'

puts 'Running...'
cfg = YAML.load_file('awaybot.yaml')
type = ARGV[0]
unless cfg.key? "#{type}_announce"
  puts "#{type} is not a known type of announcement."
  Kernel.exit 1
end

today = Date.today
puts "Running for #{today}"

ics_raw = URI.parse(ENV['FEED_URL']).read
ics = Icalendar.parse(ics_raw).first
msg = ''

if ENV['DEBUG']
  puts "Team:"
  puts ENV['NAMES'].split(';')
end

ics.events.each do |event|
  puts "#{event.summary} (#{event.dtstart} - #{event.dtend})" if ENV['DEBUG']
  name = (/[^\(]+/.match event.summary)[0].strip
  unless ENV['NAMES'].split(';').include? name
    puts "#{name} not in team"
    next
  end
  first_name = name
  away_start = event.dtstart - 0
  away_end = event.dtend - 1
  return_day = away_end + 1
  # people don't return on the weekend, bump the return day to monday
  return_day += 1 while return_day.saturday? || return_day.sunday?
  away_range = away_start..away_end
  away_duration = (away_end - away_start).to_i + 1
  # subtract any weekends from the duration
  away_range.each do |date|
    away_duration -= 1 if date.saturday? || date.sunday?
  end
  look_range =
    today..(today + cfg["#{type}_announce"]['look_forward_days'])
  next if (away_range.to_a & look_range.to_a).empty?
  puts "Message calc..."
  if away_start > today
    if away_duration == 1
      msg += "#{first_name} is off for the day on" \
        " #{away_start.strftime('%A, %B %e')}.\n"
    else
      if today.strftime('%A') == away_start.strftime('%A')
        nxt = 'next '
      else
        nxt = ''
      end
      msg += "#{first_name} is off for #{away_duration} days starting" \
        " #{nxt}#{away_start.strftime('%A, %B %e')} until" \
        " #{away_end.strftime('%A, %B %e')}.\n"
    end
  else
    if away_end - today > 0
      text_return = ChronicDuration.output(
        (return_day - today) * 60 * 60 * 24, weeks: true, format: :long, units: 2
      )
      msg += "#{first_name} is off today, returning in #{text_return}.\n"
    else
      msg += "#{first_name} is off today.\n"
    end
  end
end

if msg != '' && !today.saturday? && !today.sunday?
  msg = "Good morning! Here's who's off for the next" \
    " #{cfg["#{type}_announce"]['look_forward_days']} days.\n#{msg}"
  puts msg
  slack = Slack::Notifier.new ENV['SLACK_HOOK_URL']
  slack.ping msg
end
