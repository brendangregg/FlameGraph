#!/usr/bin/ruby
#
# Usage:
#
#   $ sudo trace-cmd record -p function_graph -l do_linkat
#   $ sudo trace-cmd report | MIN_LATENCY_US=500 ruby stackcollapse-trace-cmd.rb | flamegraph.pl --hash --colors=perl --flamechart > flamechart.svg

stack = []
buffer = []

MIN_LATENCY_US = ENV['MIN_LATENCY_US']&.to_i || 1000

STDIN.each_line do |line|
  # gitaly-3521172 [019] 8001008.806633: funcgraph_entry:                   |  do_linkat() {
  # gitaly-3521172 [019] 8001008.806634: funcgraph_entry:                   |    filename_lookup() {
  # gitaly-3521172 [019] 8001008.806634: funcgraph_entry:                   |      path_lookupat.isra.0() {
  # gitaly-3521172 [019] 8001008.806635: funcgraph_entry:                   |        path_init() {
  # gitaly-3521172 [019] 8001008.806635: funcgraph_entry:                   |          nd_jump_root() {
  # gitaly-3521172 [019] 8001008.806636: funcgraph_entry:        0.349 us   |            set_root();
  # gitaly-3521172 [019] 8001008.806636: funcgraph_exit:         1.170 us   |          }
  # gitaly-3521172 [019] 8001008.806637: funcgraph_exit:         1.779 us   |        }

  if m = /^\s+\S+\s+\[\d+\]\s+\d+\.\d+:\s+funcgraph_entry:\s+\|\s+(.+)\(\)\s+\{$/.match(line)
    func = m[1]
    stack << [func, 0]
  elsif m = /^\s+\S+\s+\[\d+\]\s+\d+\.\d+:\s+funcgraph_entry:\s+[+!#]?\s(\d+\.\d+) us\s+\|\s+(.+)\(\);$/.match(line)
    latency = m[1].to_f
    func = m[2]
    buffer << "#{(stack.map(&:first) + [func]).join(';')} #{latency}"
    stack.each do |frame|
      frame[1] += latency
    end
  elsif m = /^\s+\S+\s+\[\d+\]\s+\d+\.\d+:\s+funcgraph_exit:\s+[+!#]?\s(\d+\.\d+) us\s+\|\s+\}$/.match(line)
    func, latency_consumed = stack.pop
    latency = m[1].to_f
    buffer << "#{(stack.map(&:first) + [func]).join(';')} #{(latency - latency_consumed)}"

    stack.each do |frame|
      frame[1] += (latency - latency_consumed)
    end

    if stack.size == 0
      buffer << 'dummy 0'
      puts buffer if latency > MIN_LATENCY_US
      buffer = []
    end
  elsif m = /^(CPU \d+ is empty|cpus=\d+)$/.match(line)
  else
    warn "unknown line: #{line}"
  end
end
