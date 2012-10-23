#!/usr/bin/python

import argparse
import sqlite3
import codecs
import re
import sys
import time

def main():
    parser = argparse.ArgumentParser(description="Search companies database for connections between people (given as a list of personal ID numbers) and corporations.")

    parser.add_argument('database', help="The database file to search.")
    parser.add_argument('pids', help="A file containing personal ID numbers to search for, one ID per line.")
    parser.add_argument('--out', help="File to write output to", action='store')
    parser.add_argument('--tsv', help="Tab-separated formatting", action='store_true')
    parser.add_argument('--collapse', help="Attempt to prune duplicate entries.", action='store_true')

    args = parser.parse_args()

    # Open input files
    ifile = codecs.open(args.pids,mode='r',encoding='utf-8')

    db_conn = sqlite3.connect(args.database)
    db_conn.row_factory = sqlite3.Row

    # Open output files
    ofile = None
    if args.out != None:
        ofile = codecs.open(args.out,mode='w',encoding='utf-8')
        sys.stdout = ofile

    db = db_conn.cursor()

    ids = set(ifile) # Remove people who donated twice
    for line in ids:
        piradi = line.strip()
        try: 
            validate_personal_id(piradi)
            if not args.tsv:
                print("Searching for personal id {0}.".format(piradi))
        except ValueError as e:
            print e

        # Locate the person
        people = find_person(db,piradi)
        for pers in people:
            if not args.tsv:
                print(u"**Found {0}, {1}, {2}, {3}".format(pers['pid'],pers['name'],pers['address'],pers['personal_number']))

            #print(u"######## CHECKING PAGES ##########")
            #qstr = """SELECT * FROM page_to_person 
            #       JOIN company ON page_to_person.cid = company.cid
            #       WHERE page_to_person.pid = '{0}';""".format(pers['pid'])
            corps = connections_by_page(db,pers['pid']).fetchall()
            if args.collapse and len(corps) > 0:
                corps = collapse_pages(corps)
            for c in corps:
                if not args.tsv:
                    print(u"{0}, {1}, {2}, {3}".format(c['cid'],c['comp_name'],c['role'],c['id_code']))
                else:
                    print(u'{}\t{}\t{}\t{}\t{}\t{}'.format(pers['name'],pers['address'],pers['personal_number'],c['comp_name'],c['role'],c['id_code']))
            #print(u"######## CHECKING EXTRACTS ########")
            #qstr = """SELECT * FROM person_to_extract
            #       JOIN company on person_to_extract.cid = company.cid
            #       JOIN extracts on person_to_extract.eid = extracts.eid
            #       WHERE person_to_extract.pid = '{0}';""".format(pers['pid'])
            #corps = db.execute(qstr)
            corps = connections_by_extract(db,pers['pid']).fetchall()
            if args.collapse and len(corps) > 0:
                corps = latest_extracts(corps)
            for c in corps:
                if not args.tsv:
                    print(u"{0}, {1}, {2}, {3}, {4}".format(c['cid'],c['comp_name'],c['role'],c['id_code'],c['prep_date']))
                else:
                    print(u'{}\t{}\t{}\t{}\t{}\t{}\t{}'.format(pers['name'],pers['address'],pers['personal_number'],c['comp_name'],c['role'],c['id_code'],c['prep_date']))


        ############
        ### DONE ###
        ############
        if not args.tsv:
            print("========================")
    ifile.close()
    if args.out != None:
        ofile.close()
    
def validate_personal_id(pid):
    pattern = re.compile('^\d{11,11}$') # A personal number is 11 digits
    if len(pid) != 11:
        raise ValueError(u"ID Number must be 11 characters: {0}".format(pid))
    if pattern.match(pid) == None:
        raise ValueError(u"ID number must contain only digits. {0}".format(pid))


def collapse_pages(rows):
    """Returns only one page listing per person/company/role"""
    latest = []
    latest.append(rows[0])
    prev = rows[0]
    for r in rows:
        if r['cid'] != prev['cid'] or r['role'] != prev['role']:
            latest.append(r)
            prev = r
    return latest

def latest_extracts(rows):
    """Returns only the rows representing the most recent extract for
    each company. Assumes an array grouped by company ID."""
    collapsed = [] # final output array
    #collapsed.append(rows[0])
    prev = rows[0]
    temp = [] # temporary storage array
    
    #pivot_date = time.strptime(pivot['prep_date'],"%d/%m/%Y %H")
    for r in rows:
        # Get a list of company ids
        if r['cid'] == prev['cid']:
            temp.append(r)
            prev = r
        else: # New block of ids, so dump the newest extract in previous block
            # Sort temp by date, newest first
            temp.sort(key=lambda i: time.strptime(i['prep_date'],"%d/%m/%Y %H")) # Newer dates are bigger than older ones.
            for t in reversed(temp):
                # Newest date will be first, add all entries from that
                # extract.
                if t['prep_date'] == temp[0]['prep_date']:
                    collapsed.append(t)
                else:
                    break
            temp = []
            temp.append(r)
            prev = r
    
    # Sort and dump whatever's left over in temp
    temp.sort(key=lambda i: time.strptime(i['prep_date'],"%d/%m/%Y %H")) # Newer dates are bigger than older ones.
    for t in reversed(temp):
    # Newest date will be first, add all entries from that extract.
        if t['prep_date'] == temp[-1]['prep_date']:
            collapsed.append(t)
        else:
            break

    return collapsed

# Finds a person based on their Georgian Personal Number
def find_person(cursor,pnum):
    qstr = "SELECT * FROM people WHERE people.personal_number LIKE '%{0}%';".format(pnum)
    return cursor.execute(qstr)

# Finds company connections based on an internal row ID into the people table
def connections_by_page(cursor,pid):
    qstr = """SELECT * FROM page_to_person 
           JOIN company ON page_to_person.cid = company.cid
           WHERE page_to_person.pid = '{0}';""".format(pid)
    return cursor.execute(qstr)

# Finds company connections based on an internal row ID into the people table
def connections_by_extract(cursor,pid):
    qstr = """SELECT * FROM person_to_extract
           JOIN company on person_to_extract.cid = company.cid
           JOIN extracts on person_to_extract.eid = extracts.eid
           WHERE person_to_extract.pid='{0}' ORDER BY company.cid;""".format(pid)
    return cursor.execute(qstr)

if __name__ == "__main__":
    main()
