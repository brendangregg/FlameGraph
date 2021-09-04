#!/usr/bin/env python

import csv
import datetime
import json
import sys
import os
import random


def get_tests(prefix, json_part, result):
    run = True
    try:
        if json_part['tests']:
            run = True
    except:
        run = False
    if run:
        for test in json_part['tests']:
            try:
                keys = list(test.keys())
                if 'start' and 'stop' in keys:
                    prefix += test['type']
                    start = test['start']
                    stop = test['stop']

                    datetime_object_start = datetime.datetime.strptime(start, "%Y-%m-%dT%H:%M:%SZ")
                    datetime_object_stop = datetime.datetime.strptime(stop, "%Y-%m-%dT%H:%M:%SZ")

                    stop_hour = datetime_object_stop.strftime("%H")
                    stop_minute = datetime_object_stop.strftime("%M")
                    stop_second = datetime_object_stop.strftime("%S")

                    start_hour = datetime_object_start.strftime("%H")
                    start_minute = datetime_object_start.strftime("%M")
                    start_second = datetime_object_start.strftime("%S")

                    hour = (int(stop_hour) - int(start_hour))
                    minute = (int(stop_minute) - int(start_minute))
                    second = (int(stop_second) - int(start_second))

                    second += minute * 60
                    second += hour * 3600

                    name = test['name']

                    disallowed_characters = '\'\"\n, '
                    for character in disallowed_characters:
                        name = name.replace(character, '_')

                    prefix += '-' + name + ';'
                    with open(result, 'a', newline='') as f:
                        writer = csv.writer(f, dialect='excel')
                        time = str(second)
                        writer.writerow([prefix + name + ' ' + time])
                else:
                    pass

            except:
                pass
            get_tests(prefix, test, result)
    else:
        pass


def create_json_from_js(js_file):
    with open(js_file) as f:
        f = f.read()
        # strips unwanted parts from js file
        index = f.find('(')
        f = f[index + 1:][::-1]
        index = f.find('}')
        final_json = f[index:][::-1]

        # creates new json file
        file_name = 'result_from_js.json'
        checked_file = check_file(file_name)
        file = open(checked_file, 'w')
        file.write(final_json)
        file.close()

    print('Json file %s successfully created from %s' % (checked_file, js_file))
    return checked_file


def change_file_name(file):
    if file.endswith('.csv'):
        # strips '.csv' ending
        file = file[::-1][4:][::-1]
        added_int = random.randint(0, 100)
        file += str(added_int)
        file += '.csv'

    if file.endswith('.json'):
        # strips '.json' ending
        file = file[::-1][5:][::-1]
        added_int = random.randint(0, 100)
        file += str(added_int)
        file += '.json'

    return str(file)


def check_file(file_name):   # checks if file exists
    if os.path.isfile(file_name):
        file = change_file_name(file_name)
        final_file = check_file(file)
    else:
        return file_name
    return final_file


if __name__ == '__main__':
    try:
        sys.argv[2]
    except IndexError:  # no arguments give
        print('parse_json.py takes 2 additional arguments')
        print('parse_json.py {json/js file} {result csv file}')
        quit()

    js_json_file = sys.argv[1]

    result = sys.argv[2]

    if result.endswith('.csv'):
        result = result
    else:
        result = result + '.csv'

    result = check_file(result)

    # deletes content that is in result file
    with open(result, 'w') as res:
        pass

    created_json = False
    if js_json_file.endswith('.js'):
        created_json = create_json_from_js(js_json_file)

    if created_json:
        file = created_json
    else:
        file = js_json_file

    with open(file) as f:
        working_dict = json.load(f)

    prefix = ""
    get_tests(prefix, working_dict, result)
    print('%s file successfully created' % result)

    # replace CRLF ending into LF ending
    WINDOWS_LINE_ENDING = b'\r\n'
    UNIX_LINE_ENDING = b'\n'

    with open(result, 'rb') as open_file:
        content = open_file.read()

    content = content.replace(WINDOWS_LINE_ENDING, UNIX_LINE_ENDING)

    with open(result, 'wb') as open_file:
        open_file.write(content)
