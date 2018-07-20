# Skip header and border
NR < 9 { next }
match($0, /^\-+$/) { next }

{
	spaces = count_spaces($0);
	while (depth_stack_size() > 0 && spaces <= depth_stack_top()) {
		value_stack_pop();
		depth_stack_pop();
	}
	value_stack_push($1);
	depth_stack_push(spaces);
}

$8 != "" && $8 != "0ms" {print value_stack_combine() " " substr($8, 0, length($8) - 2)}

function count_spaces(s) {
	match(s, /^ */);
	return RLENGTH;
}

function value_stack_combine() {
	ret = "";
	for (i = 0; i < value_stack_pos; i++) {
		ret = ret value_stack_array[i];
        if (i < value_stack_pos - 1) {
		    ret = ret ";";
        }
	}
	return ret;
}

function value_stack_push(val) {
        value_stack_array[value_stack_pos++] = val;
}

function value_stack_pop() {
        return (value_stack_size() < 0) ? "ERROR" : value_stack_array[--value_stack_pos];
}

function value_stack_top() {
        return value_stack_array[value_stack_pos - 1];
}
function value_stack_size() {
        return value_stack_pos;
}

function depth_stack_push(val) {
        depth_stack_array[depth_stack_pos++] = val;
}

function depth_stack_pop() {
        return (depth_stack_size() < 0) ? "ERROR" : depth_stack_array[--depth_stack_pos];
}

function depth_stack_top() {
        return depth_stack_array[depth_stack_pos - 1];
}
function depth_stack_size() {
        return depth_stack_pos;
}
