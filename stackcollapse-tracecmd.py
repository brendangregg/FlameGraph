#!/usr/bin/python3
import argparse
import re


""" funcgraph example
sysctl-1757  [000]  1718.797855: funcgraph_entry:                   |        __kmalloc_track_caller() {
sysctl-1757  [000]  1718.797855: funcgraph_entry:        0.159 us   |          kmalloc_slab();
sysctl-1757  [000]  1718.797855: funcgraph_entry:                   |          _cond_resched() {
sysctl-1757  [000]  1718.797856: funcgraph_entry:        0.159 us   |            rcu_all_qs();
sysctl-1757  [000]  1718.797856: funcgraph_exit:         0.466 us   |          }
sysctl-1757  [000]  1718.797856: funcgraph_entry:        0.159 us   |          should_failslab();
sysctl-1757  [000]  1718.797856: funcgraph_entry:        0.165 us   |          memcg_kmem_put_cache();
sysctl-1757  [000]  1718.797857: funcgraph_exit:         1.789 us   |        }
sysctl-1757  [000]  1718.797857: funcgraph_entry:                   |        __check_object_size() {
sysctl-1757  [000]  1718.797857: funcgraph_entry:        0.166 us   |          check_stack_object();
sysctl-1757  [000]  1718.797857: funcgraph_entry:        0.174 us   |          __virt_addr_valid();
sysctl-1757  [000]  1718.797858: funcgraph_entry:        0.271 us   |          __check_heap_object();
sysctl-1757  [000]  1718.797858: funcgraph_exit:         1.540 us   |        }
sysctl-1757  [000]  1718.797859: funcgraph_entry:        0.576 us   |        kfree();
sysctl-1757  [000]  1718.797859: funcgraph_entry:        0.174 us   |        kfree();
"""


class FtraceAnalyzer:
    def __init__(self, gen_flamegraph=False, merge=False):
        self.regexp_arr = {
            "fentry": r".+funcgraph_entry.+\|\s+(\w+).+{",
            "fentry_single": r".+\:\s+(?P<time>\d+(\.\d+)*)\s+us\s+\|\s+(?P<sym_name>\w+).+;",
            "fexit": r".+funcgraph_exit\:.+\s+(?P<time>\d+(\.\d+)*)\sus\s+\|\s+}",
        }
        self.gen_flame = gen_flamegraph
        self.merge = merge
        self.time = 0.0
        self.time_stack = []

    def get_func_entry(self, line):
        m_fentry = re.search(self.regexp_arr['fentry'], line)

        if m_fentry:
            sym_name = m_fentry.expand(r"\1")
            return sym_name
        return None

    def get_single_func_entry(self, line):
        m_fentry_s = re.search(self.regexp_arr['fentry_single'], line)

        if m_fentry_s:
            time = m_fentry_s.group(r"time")
            sym_name = m_fentry_s.group(r"sym_name")
            return float(time), sym_name
        return None

    def get_func_exit(self, line):
        m_fexit = re.search(self.regexp_arr['fexit'], line)

        if m_fexit:
            time = m_fexit.group(r"time")
            return float(time)
        return None

    def fentry_works(self, symbol_names, func_name, stack):
        # accumulate the symbol counts
        stack.append(func_name)

        if self.gen_flame:
            # When a new function is encountered, the previous accumulated
            # function time need to put to the time stacks because the
            # accumulated time for each caller need to be recalculated. And
            # this will be popped out again when the caller exits.
            self.time_stack.append(self.time)
            self.time = 0.0

    def update_symbol_meta(self, sym_dict, meta_type, value, init_val):
        sym_dict[meta_type] = sym_dict.setdefault(meta_type, init_val)
        sym_dict[meta_type] += value


    def single_fentry_works(self, symbol_names, func_name, stack, time):
        # Create the dict for function name
        symbol_names[func_name] = symbol_names.setdefault(func_name, {})
        sym_dict = symbol_names[func_name]
        # Increase the count and time for the function name
        self.update_symbol_meta(sym_dict, "count", 1, 0)
        self.update_symbol_meta(sym_dict, "time", time, 0.0)

        # Regarding the callstack, the time/count is accumulated separately for
        # accurate calculation.
        sym_dict["callstack"] = sym_dict.setdefault("callstack", {})
        callstack = ";".join(stack) + ";" + func_name if stack else func_name
        sym_dict_csk = sym_dict["callstack"]
        sym_dict_csk[callstack] = sym_dict_csk.setdefault(callstack, {})
        self.update_symbol_meta(sym_dict_csk[callstack], "count", 1, 0)
        self.update_symbol_meta(sym_dict_csk[callstack], "time", time, 0.0)

        if self.gen_flame:
            self.time += time

    def fexit_works(self, symbol_names, stack, time):
        if not stack:
            print("The callgraph is broken, \'}\' is redundant\n")
            return

        func_name = stack[-1]
        stack.pop()
        # Create the dict for function name
        symbol_names[func_name] = symbol_names.setdefault(func_name, {})
        sym_dict = symbol_names[func_name]
        # Increase the count and time for the function name
        self.update_symbol_meta(sym_dict, "count", 1, 0)
        self.update_symbol_meta(sym_dict, "time", time, 0.0)

        sym_dict["callstack"] = sym_dict.setdefault("callstack", {})
        callstack = ";".join(stack) + ";" + func_name if stack else func_name
        sym_dict_csk = sym_dict["callstack"]
        sym_dict_csk[callstack] = sym_dict_csk.setdefault(callstack, {})
        self.update_symbol_meta(sym_dict_csk[callstack], "count", 1, 0)
        self.update_symbol_meta(sym_dict_csk[callstack], "time", time, 0.0)

        if self.gen_flame:
            # itself = total func time - callee time
            self.update_symbol_meta(sym_dict_csk[callstack], "itself",
                                    time - self.time, 0.0)
            # When finishing a function, the parser needs to pop the previous
            # accumulating time. However, the ending funciton total time needs
            # to be counted to ensure not ignoring the previous function.
            self.time = self.time_stack.pop()
            self.time += time

    def cal_avg(self, symbol_names):
        for sym in symbol_names:
            symbol_names[sym]["avg_time"] = symbol_names[sym]["time"] / \
                symbol_names[sym]["count"]

    def parse_files(self, name, symbol_names):
        stack = []
        try:
            with open(name, 'r') as fp:
                print("Parsing " + name)
                ln = fp.readline()
                while ln:
                    # The function would call other functions
                    sym_name = self.get_func_entry(ln)
                    if sym_name is not None:
                        self.fentry_works(symbol_names, sym_name, stack)
                        ln = fp.readline()
                        continue

                    # Single function needs to save the time and callstack
                    args = self.get_single_func_entry(ln)
                    if args is not None:
                        time, sym_name = args
                        if sym_name is not None:
                            self.single_fentry_works(symbol_names, sym_name,
                                                     stack, time)

                        ln = fp.readline()
                        continue

                    # Get function exit
                    time = self.get_func_exit(ln)
                    if time is not None:
                        self.fexit_works(symbol_names, stack, time)
                        ln = fp.readline()
                        continue

                    # Ignore garbage
                    if ln[0].isalnum():
                        print("Ignore:{}".format(ln))
                    ln = fp.readline()
                    continue

        except OSError:
            print("Cannot read \"%s\", May be it doesn't exist!" % name)
            return

        # Before finishing, we need to calculate the average time
        self.cal_avg(symbol_names)

        return symbol_names

    def build_flamegraph_list(self, fp, sym_table, fprefix):
        for sym_name in sym_table:
            cstacks = sym_table[sym_name]["callstack"]
            for cs in cstacks:
                itself_time = cstacks[cs].get("itself", None)
                # If the callstack has itself, it means the function has callee
                # and the time itself is the total time minus the the sepnt on
                # callees.
                if itself_time is not None:
                    itself_time *= 1000  # rebase to nanosecond
                    new_cs = fprefix + ";" + cs + " " + str(itself_time) + "\n"
                    fp.write(new_cs)
                else:
                    # If there is no itself, it's the single function call. So,
                    # we just get the time and rebase to nanosecond.
                    new_cs = fprefix + ";" + cs + " " + \
                        str(cstacks[cs].get("time") * 1000 ) + "\n"

                    fp.write(new_cs)

    def generate_flamegraph(self, files_dict):
        try:
            for i, f in enumerate(files_dict):
                sym_table = files_dict[f]
                fprefix = f.split('.')[0]  # Split out the file name
                mode = "w"
                if self.merge:
                    fname = "merged_flamegraph.log"
                    if i == 0:
                        print("[Flamegraph]: {} is generated".format(fname))

                    if i:  # Use the apppend mode after the first merged file
                        mode = "a"
                else:
                    fname = fprefix + "_" + "flamegraph.log"
                    print("[Flamegraph]: {} is generated".format(fname))
                with open(fname, mode) as fp:
                    self.build_flamegraph_list(fp, sym_table, fprefix)

        except OSError:
            print("Cannot write \"{:s}\"!".format(f))
            return


class SymbolAnalyzer:
    def __init__(self, f_dicts):
        # The symbol table is generated for each funcgraph file and saved in
        # dictionary.
        self.files_dict = f_dicts

    def sort(self, sort_key="count"):
        # Iterate every symbol table to print out the assigned sorted keys
        for f in self.files_dict:
            symbol_table = self.files_dict[f]
            sym_cnt_lst = [[symbol_table[s][sort_key], s] for s in symbol_table.keys()]
            sorted_lst = sorted(sym_cnt_lst, reverse=True)
            print("\n{f} performance analysis ({sort_key} basis)".format(**locals()))
            print("{:30s} {:<10s} {:<20s} {:<20s}".format("symbol name", "count", "time (us)", "time avg (us)"))
            for entry in sorted_lst:
                count, sym = entry[0], entry[1]
                sym_dict = symbol_table[sym]
                print("{:30s} {:<10d} {:<20.5f} {:<20.5f}".format(sym, sym_dict['count'], sym_dict['time'], sym_dict['avg_time']))


def initialize_arguments():
    """Assign the default search folder and the arguments"""

    parser = argparse.ArgumentParser(
        description='Description for ftrace funcgraph log analysis tool')
    parser.add_argument(
        'file_name',
        type=str,
        nargs='+',
        help='Input at least one ftrace funcgraph file name to be analyzed')
    parser.add_argument(
        '-f', '--flamegraph',
        action='store_true',
        help='Generate the flamegraph input format for FlameGraph tool',
        default=argparse.SUPPRESS)
    parser.add_argument(
        '-m', '--merge',
        action='store_true',
        help='Generate the flamegraph input format with input logs together',
        default=False)
    return parser


def main():
    parser = initialize_arguments()
    args = parser.parse_args()
    gen_flamegraph = False
    if hasattr(args, "flamegraph"):
        gen_flamegraph = True
    fa = FtraceAnalyzer(gen_flamegraph, args.merge)

    files_dict = {}
    # Parse the file names provided in command line
    for f in args.file_name:
        files_dict[f] = fa.parse_files(f, {})

    # Generate the Flamegraph input format
    if gen_flamegraph:
        fa.generate_flamegraph(files_dict)

    # Print out the count basis sorting with the symbol
    sa = SymbolAnalyzer(files_dict)

    # Sort the symbol based on count/time
    sa.sort("count")
    sa.sort("time")
    sa.sort("avg_time")


if __name__ == "__main__":
    main()
