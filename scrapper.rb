#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems'
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'json'
require 'logger'
require 'pdf/reader'
require './libSC.rb'
require 'sqlite3'
require 'ping'


#Sole entrepreneur 	1
#SPS 			2
#Cooperative 		3
#LTD			4
#Joint Stock Co.	5
#Society limited	6
#non-profit		7
#Legal entity		10
#Foreign enterprise	26
#Foreign non-profit	27
#Business Partnership	28

DB = SQLite3::Database.open "scrapper_db.db"
DB.busy_timeout(100)

BASE_URL = "https://enreg.reestri.gov.ge"
HDR = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
@br = Mechanize.new { |b|
  b.user_agent_alias = 'Mac Safari'
  b.read_timeout = 1200
  b.max_history=0
  b.retry_change_requests = true
  b.verify_mode = OpenSSL::SSL::VERIFY_NONE}

@gent = Mechanize.new
@gent.pluggable_parser.pdf = Mechanize::Download

$current_cid
$comp_in_db

class String
  def pretty
    self.strip.gsub(/\n|\t|\r/,' ').gsub(/\s+/," ").strip
  end
end

class Array
  def pretty
    self.collect{|a| a.strip}
  end
end

def pretify(str)
  if str==nil
    return nil
  end
  while str.start_with?(",") or str.start_with?(" ") or str.start_with?("\n") or  str.start_with?("\r")
    str[0] = ''
  end
  while str.end_with?(",") or str.end_with?(" ") or str.end_with?("\n") or  str.end_with?("\r")
    str = str.chop
  end
  if str == ""
    return nil
  end
  return str
end

#this method returns the fist page of a company, in case of lost connection it waits for connection
def fetch_pg2(cid)
  params2 = {"c"=>"app","m"=>"show_legal_person", "legal_code_id"=>cid}
  pg2 = nil
  begin
   Timeout::timeout(5) {
      pg2 = @br.post(BASE_URL + "/main.php",params2,HDR)
  }
  rescue Exception => exc
    puts "ERROR: #{exc.message} in scrape() pg2! \nTrying again in 5 seconds."
    sleep 5
    begin
      #continues if connection is active
      break if Ping.pingecho("google.com",10,80)
      puts "waiting for ping google.com"
      sleep 2
    end while(true)
    return fetch_pg2(cid)
  end
  return pg2
end

def haskeyword(src)
    ["ყადაღა/აკრძალვა","ხელმძღვანელობაზე", "წარმომადგენლობაზე","უფლებამოსილი" "პირები",
      "დამფუძნებლები","წილი","ყადაღა/აკრძალვა", "პარტნიორები", "საგადასახადო გირავნობა/იპოთეკის უფლება",
    "მოძრავ ნივთებსა და არამატერიალურ ქონებრივ", "მოვალეთა რეესტრი", "ინფორმაცია ლიკვიდაციის შესახებ",
    "პროკურისტები", "სუბიექტი", "რეორგანიზაცია"].each do |key_word|
        return true if src.include?(key_word)
    end
    return false
end

def scrape(data)
      records = Hash.new("")
      Nokogiri::HTML(data).xpath(".//table[@class='main_tbl shadow']/tbody/tr").each{|tr|
        td = tr.xpath("td")
        if td.length < 6
          puts tr.inner_html
          next
        end
        cid = attributes(td[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
        link = BASE_URL + "/main.php?c=app&m=show_legal_person&legal_code_id=#{attributes(td[0].xpath('./a'),'onclick').split('(').last.gsub(')','')}"
        records["link"] = link
       
        begin
         pg2 = fetch_pg2(cid)
        end while pg2==nil

        #scraping table with info on the second page
        Nokogiri::HTML(pg2.body).xpath(".//table[@class='mytbl']/tbody/tr").each{|tr|
            td2 = tr.xpath("td")
            if td2.length != 2
              #puts tr.inner_html
              next
            end
            col1 = s_text(td2[0].xpath("./text()"))
            col2 = s_text(td2[1])
            if col2 == "" or col2 == " "
              col2 = nil
            end
            records[col1] = col2
            #puts col1 + " =>" + records[col1]

        }
      if(records != nil )
        insert_comp(records)
      else
        next
      end
      sleep 0.25

      Nokogiri::HTML(pg2.body).xpath(".//div[@id='container']/table[caption[text() = 'განცხადებები']]/tbody/tr").each{|tr|
          td3 = tr.xpath("td")
          app_id = attributes(td3[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
          get_add(app_id)
        }

      Nokogiri::HTML(pg2.body).xpath(".//div[@id='container']/table[caption[text() = 'სკანირებული დოკუმენტები']]/tbody/tr").each{|tr|
        scols = tr.xpath("td")
        s_link = attributes(scols[0].xpath("./a"),"href")
        s_fname = scols[0].xpath("./a").text()
        puts "INFO EXTRACT PAGE comp = #{records["საიდენტიფიკაციო კოდი"]} link = #{s_link} fname = #{s_fname}"
        if s_link != nil
          insert_scan(s_link, nil, s_fname)
        end
      }
	    puts "\n\n:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n\n"
	}
end

#inserts scan-doc info to the database, in case the link is already in the database the program reports it
#TODO in case the scan-doc belong to more than 1 company shout!!
def insert_scan(link, date, file_name)
  stm = DB.prepare("SELECT * FROM scans WHERE link_to_scan = ?")
  stm.bind_params(link)
  result = stm.execute
  ret_val = 0
  if result.next()==nil
    max_row = DB.execute("SELECT MAX(sid) FROM scans")
    new_sid = Integer(max_row[0][0]) + 1
    #a new scan-doc is inserted to a company that was scrapped previously
    if $comp_in_db == true
      alrt_bd = Hash.new
      alrt_bd["cid"] = $current_cid
      alrt_bd["sid"] = new_sid
      alrt_bd["link"] = link
      alrt_bd["fname"] = file_name
      alert(4, alrt_bd)
    end
    DB.execute("INSERT INTO scans(cid, sid, date, link_to_scan, file_name) VALUES(:cid, :sid, :date, :link_to_scan, :file_name)",
    "cid"=>$current_cid,
    "sid"=>new_sid,
    "date"=>date,
    "link_to_scan"=>link,
    "file_name" => file_name)
    puts "Scan Inserted from company page (pg2): cid = #{$current_cid}; sid = #{new_sid}; date = #{date}; link=#{link}; file name = #{file_name}"
    return new_sid
  else
    result.reset()
    puts "THE LINK TO THE SCAN IS ALREADY IN THE DATABASE"
    result.each do |row|
      puts "Database: cid = #{row[0]}; sid = #{row[1]}; date = #{row[2]}; link = #{row[3]}; file name = #{row[4]}"
      puts "Inserting: cid = #{$current_cid}; sid = #{new_sid}; date = #{date}; link=#{link}; file name = #{file_name}"
      ret_val = row[0]
    end
    return ret_val
  end
end



def pdf_parser(file, link)
  return_val = -1
	extract_data = Hash.new("")
	filename = File.expand_path(file)
  begin
	PDF::Reader.open(filename) do |reader|
	  #reader.pages.each do |page|
      txt = reader.page(1).text
      previous_par = nil
      txt.each do |line|
        words = line.gsub(/[\n]/, '').split(":")
        #puts "word 1 = #{words[0]}word 2 = #{words[1]}"

        if previous_par == "იურიდიული მისამართი" and words[0]!= "ელექტრონული ფოსტა" and words[0]!= "საიდენტიფიკაციო კოდი" and words[0]!= "ფაქტობრივი მისამართი"
          if extract_data["იურიდიული მისამართი"] != nil
            buffer = extract_data["იურიდიული მისამართი"] + words[0]
          end
          extract_data[previous_par] = buffer
          previous_par = words[0]
        else
          extract_data[words[0]] = words[1]
          previous_par = words[0]
        end
      end
#      puts "Application Number = #{extract_data["განაცხადის ნომერი"]}"
#      puts "b_number= #{extract_data["განაცხადის რეგისტრაციის ნომერი"]}"
#      puts "Date of preparation of an extract = #{extract_data["ამონაწერის მომზადების თარიღი"]}"
#      puts "name = #{extract_data["საფირმო სახელწოდება"]}"
#      puts "adress = #{extract_data["იურიდიული მისამართი"]}"
#      puts "Identification Code = #{extract_data["საიდენტიფიკაციო კოდი"]}"
#      puts "legal form = #{extract_data["სამართლებრივი ფორმა"]}"
#      puts "email = #{extract_data["ელექტრონული ფოსტა"]}"
#      puts "state reg date = #{extract_data["სახელმწიფო რეგისტრაციის თარიღი"]}"
#      puts "the reg authority = #{extract_data["მარეგისტრირებელი ორგანო"]}"
#      puts "IRA = #{extract_data["საგადასახადო ინსპექცია"]}"
      stm = DB.prepare("SELECT * FROM extracts WHERE reg_number = ?")
      stm.bind_params(extract_data["განაცხადის რეგისტრაციის ნომერი"])
      result = stm.execute

      if result.next() == nil
          max_eid = DB.execute("SELECT MAX(eid) FROM extracts")
          new_eid = Integer(max_eid[0][0]) + 1
          ext_id = new_eid
          DB.execute("INSERT INTO extracts(cid, eid, reg_number, application_num, prep_date, address, email, reg_authority, tax_inspection)
          VALUES(:cid, :eid, :reg_number, :application_num, :prep_date, :address, :email, :reg_authority, :tax_inspection)",
          "cid"=>$current_cid,
          "eid"=>new_eid,
          "reg_number"=>extract_data["განაცხადის რეგისტრაციის ნომერი"],
          "application_num"=>extract_data["განაცხადის ნომერი"],
          "prep_date"=>extract_data["ამონაწერის მომზადების თარიღი"],
          "address"=>extract_data["იურიდიული მისამართი"],
          "email"=>extract_data["ელექტრონული ფოსტა"],
          "reg_authority"=>extract_data["მარეგისტრირებელი ორგანო"],
          "tax_inspection"=>extract_data["საგადასახადო ინსპექცია"])
          return_val = new_eid

          #A new extract is inserted to a company that was previously scrapped
          if $comp_in_db == true
            alrt_bd = Hash.new
            alrt_bd["cid"] = $current_cid
            alrt_bd["eid"] = new_eid
            alrt_bd["link"]= link
            alert(3, alrt_bd)
          end
       else
        puts "The Extract is already in the database."
        result.reset()
        result.each do |row|
            #puts row
            ext_id = row[1]
            return_val = row[1]
            if row[0] != $current_cid or
                row[2] != extract_data["განაცხადის რეგისტრაციის ნომერი"] or
                row[3] != extract_data["განაცხადის ნომერი"] or
                row[4] != extract_data["ამონაწერის მომზადების თარიღი"] or
                row[5] != extract_data["იურიდიული მისამართი"] or
                row[6] != extract_data["ელექტრონული ფოსტა"] or
                row[7] != extract_data["მარეგისტრირებელი ორგანო"] or
                row[8] != extract_data["საგადასახადო ინსპექცია"]

                puts "cid :> #{row[0]} != #{$current_cid}"
                puts "reg_number :> #{row[2]} != #{extract_data["განაცხადის რეგისტრაციის ნომერი"]}"
                puts "appnum :> #{row[3]} != #{extract_data["განაცხადის ნომერი"]}"
                puts "prep_date :> #{row[4]} != #{extract_data["ამონაწერის მომზადების თარიღი"]}"
                puts "address #{row[5]} != #{extract_data["იურიდიული მისამართი"]}"
                puts "email :> #{row[6]} != #{extract_data["ელექტრონული ფოსტა"]}"
                puts "autority #{row[7]} != #{extract_data["მარეგისტრირებელი ორგანო"]}"
                puts " IRA :> #{row[8]} != #{extract_data["საგადასახადო ინსპექცია"]}"
                puts "ALERT UPDATE EXTRACT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            else
                puts "The same extract."
            end
          end
        end

      #handling people in the extract
      line_array = Array.new
      reader.pages.each do |page|
        page.text.each do |line|
        line_array.push(line)
        #puts line
        end
      end

      i = 0;
      while i<line_array.length do
         if line_array[i].include?"ხელმძღვანელობაზე/წარმომადგენლობაზე უფლებამოსილი პირები" #leadership
           if line_array[i+1].include? "ხელმძღვანელობაზე/წარმომადგენლობაზე უფლებამოსილი პირები"
            j = i+1
           else
             j=i
           end

           while !haskeyword(line_array[j+1]) do
               if line_array[j+1].include?"public.reestri.gov.ge"
                 j+=1
                 next
               end
               first = line_array[j+1]
               fields = first.split(",", 2)
               puts fields
               p_n = pretify(fields[0])
               name = pretify(fields[1])
               relation = pretify(line_array[j+2])
               if relation == nil
                 relation = "Person on the board"
               end
               puts "leader=> pn:#{p_n} name:#{name} rel:#{relation}"
               if p_n != nil
                extract_person(p_n, name, relation, ext_id)
               end
              j+=2
           end
            i = j
         end


         if line_array[i].include?"დამფუძნებლები" #Founders
           if line_array[i+1].include?"დამფუძნებლები"
             j = i+1
           else
             j = i
           end

           while !haskeyword(line_array[j+1]) do
              if line_array[j+1].include?"public.reestri.gov.ge"
                 j+=1
                 next
              end
              first = line_array[j+1]
              fields = first.split(",", 2)
              p_n = pretify(fields[0])
              name = pretify(fields[1])
              puts "founder=> pn:#{p_n} name:#{name} rel: Founder"
              if p_n != nil
                extract_person(p_n, name, "Founder", ext_id)
              end
              j+=1
           end
            i = j
         end


         if line_array[i].include?"პარტნიორებიპარტნიორები" #Partners
           if line_array[i+1].include?"პარტნიორებიპარტნიორები"
             j = i+2
           else
             j = i+1
           end
           if line_array[j+1].include?"წილი"
             j = j+1
           end
           while !haskeyword(line_array[j+1]) do
              if line_array[j+1].include?"public.reestri.gov.ge"
                 j+=1
                 next
              end
              first = line_array[j+1]
              fields = first.split(",", 3)
              p_n = pretify(fields[0])
              name = pretify(fields[1])
              puts "partner=> pn:#{p_n} name:#{name} rel: Partner"
              if p_n != nil
                extract_person(p_n, name, "Partner", ext_id)
              end
              j+=1
           end
            i = j
         end


         if line_array[i].include?"დირექტორები" #directors
           if line_array[i+1].include?"დირექტორები"
             j = i+2
           else
             j = i+1
           end
           if line_array[j+1].include?"სუბიექტი"
             j = j+1
           end
           while !haskeyword(line_array[j+1]) do
               if line_array[j+1].include?"public.reestri.gov.ge"
                 j+=1
                 next
               end
               first = line_array[j+1]
               fields = first.split(",", 2)
               #puts fields
               p_n = pretify(fields[0])
               name = pretify(fields[1])
               relation = pretify(line_array[j+2])
               if relation == nil
                 relation = "Director"
               end
               puts "Director=> pn:#{p_n} name:#{name} rel:#{relation}"
               if p_n != nil
                extract_person(p_n, name, relation, ext_id)
               end
              j+=2
           end
            i = j
         end
         i+=1
      end
    end
  rescue Exception => exc
    puts "ERROR: #{exc.message} in get extract!"
    return return_val
  end
    return return_val
 end


#this method saves the extract once it is called with appropriate id's,
#calls pdf_parser to read/parse the extract and then removes the file
def get_extract(scandoc_id, app_id, link)
  ext_param = {"c"=>"mortgage","m"=>"get_output_by_id", "scandoc_id"=>scandoc_id, "app_id"=>app_id}
  begin
    Timeout::timeout(5) {
      @gent.post(BASE_URL + "/main.php",ext_param,HDR).save('./enreg.reestri.gov.ge/temp_extract.pdf')}
  rescue Exception => exc
    puts 'Downloading the extract took too long, trying again...'
    puts "ERROR: #{exc.message} in get extract!"
    while(true) do
      #continues if connection is active
      break if Ping.pingecho("google.com",10,80)
      puts "waiting for ping google.com"
      sleep 2
    end
    return get_extract(scandoc_id, app_id, link)
  end
  if  FileTest.exists?("./enreg.reestri.gov.ge/temp_extract.pdf") == false
    puts "file does not exists"
    return get_extract(scandoc_id, app_id, link)
  end
  val = pdf_parser("./enreg.reestri.gov.ge/temp_extract.pdf", link)
  File.delete("./enreg.reestri.gov.ge/temp_extract.pdf")
  return val
end





def action()
  params = {"c"=>"search","m"=>"find_legal_persons","s_legal_person_idnumber"=>"","s_legal_person_name"=>"","s_legal_person_form"=>"2"}
  pg = nil
  begin
    begin
      begin
       status = Timeout::timeout(5) {
          pg = @br.post(BASE_URL + "/main.php",params,HDR)
      }
      rescue Timeout::Error
        puts 'Fetching pg1 took too long, trying again...'
        begin
          break if Ping.pingecho("google.com",10,80)
          puts "waiting for ping google.com"
          sleep 2
        end while(true)
        next
      end
    rescue Exception => exc
      puts "ERROR: #{exc.message} in action() pg1!\nTrying again in 5 seconds."
      sleep 5
      next
    end

    scrape(pg.body)
    next_pg = attributes(Nokogiri::HTML(pg.body).xpath(".//td/a[img[contains(@src,'next.png')]]"),"onclick").scan(/legal_person_paginate\((\d+)\)/).flatten.first
    break if next_pg.nil?
    params = {"c"=>"search","m"=>"find_legal_persons","p"=>next_pg}
    sleep 0.25
  end while(true)
end


#this method returns the child page of an add of a company, in case of lost connection it waits for reconnection
def fetch_pg3(id)
 pg3 = nil
 params3 = {"c"=>"app","m"=>"show_app", "app_id"=> id}
  begin
   Timeout::timeout(5) {
   pg3 = @br.post(BASE_URL + "/main.php",params3,HDR)}
  rescue Exception => exc
    puts "ERROR: #{exc.message} in get_add() pg3! Trying again in 5 seconds."
    sleep 5
    begin
          #ping google, break if internet connection is active
          break if Ping.pingecho("google.com",10,80)
          puts "waiting for ping google.com..."
          sleep 2
    end while(true)
    return fetch_pg3(id)
  end
 return pg3
end


#goes to the last dead-end page and get the info
def get_add(id)
  page_data = Hash.new()
  pg3 = nil
  begin
    pg3 = fetch_pg3(id)
  end while pg3 == nil

  extract_list = Array.new
  scan_list = Array.new
  app_list = Array.new
  page_list = Array.new
  pg_prsn_ls = Array.new

  #Getting all the extracts in case it is a djvu file save it into the table of scandocs
   Nokogiri::HTML(pg3.body).xpath(".//div[@id='tabs-3']/div/table[caption[text() = 'მომზადებული დოკუმენტები']]/tr").each{|tr|
    rows = tr.xpath('td')
    if(rows.length < 3)
      puts rows
      next
    end
    link = attributes(rows[0].xpath("./a"),"href")
    scandoc_id = CGI.parse(link)['scandoc_id']
    app_id = CGI.parse(link)['app_id']
    dummy = rows[1].xpath("./span")
    text = s_text(dummy[0].xpath("text()"))
    extract_date = s_text(dummy[1].xpath("text()"))
    
    #check whether the document is djvu file or non-extract pdf, if true, saves the link to the file
    fname = s_text(rows[2])
    if fname.end_with?(".djvu") or !text.include?("ამონაწერი")
      puts "DEJA VU file or non-extract file encountered in the exctracts"
      stm = DB.prepare("SELECT * FROM scans WHERE link_to_scan = ?")
      stm.bind_params(link)
      result = stm.execute
      if result.next()==nil
        max_row = DB.execute("SELECT MAX(sid) FROM scans")
        new_sid = Integer(max_row[0][0]) + 1
        DB.execute("INSERT INTO scans(cid, sid, date, link_to_scan, file_name) VALUES(:cid, :sid, :date, :link_to_scan, :file_name)",
        "cid"=>$current_cid,
        "sid"=>new_sid,
        "date"=>extract_date,
        "link_to_scan"=>link,
        "file_name"=>fname)
        puts "Inserted: cid = #{$current_cid}; sid = #{new_sid}; date = #{extract_date}; link=#{link}; file name = #{fname}"
        scan_list.push(new_sid)
        if $comp_in_db == true
          if $comp_in_db == true
            alrt_bd = Hash.new
            alrt_bd["cid"] = $current_cid
            alrt_bd["sid"] = new_sid
            alrt_bd["link"] = link
            alrt_bd["fname"] = fname
            alert(4, alrt_bd)
          end
        end

      else
        result.reset()
        puts "THE LINK TO THE SCAN IS ALREADY IN THE DATABASE"
        result.each do |row|
          scan_list.push(row[1])
          puts "Database: cid = #{row[0]}; sid = #{row[1]}; date = #{row[2]}; link = #{row[3]}; file name = #{row[4]}"
          puts "Inserting: cid = #{$current_cid}; sid = #{new_sid}; date = #{extract_date}; link=#{link}; file name = #{fname}"
        end
      end
    else
      eid = get_extract(scandoc_id, app_id, link)
      extract_list.push(eid)
    end
   }

    #Preparing page data to be inserted in the database
    b_number = s_text((Nokogiri::HTML(pg3.body).xpath(".//tr[td[contains(text(), 'რეგისტრაციის ნომერი')]]/td/span[text()]")))
    page_data["b_number"] = b_number
    page_data["property_num"] = id
    page_data["cid"] = $current_cid
    Nokogiri::HTML(pg3.body).xpath(".//div[@id = 'application_tab']/table/tbody/tr").each{|tr|
    row_data = tr.xpath("td")
    if row_data.length != 2
      next
    end
    val1 = s_text(row_data[0])
    val2 = s_text(row_data[1])
    if val2 == "" or val2 == " "
      val2 = nil
    end
    page_data[val1] = val2
   }
   #the id of the current inserted page
   page_id = insert_page(page_data)
   page_list.push(page_id)

   #checking for people whose name is written in corresponding entries
   if page_data["განმცხადებელი"] != nil
     pid = insert_person(page_data["განმცხადებელი"])
     pg_prsn_ls.push({pid, "განმცხადებელი"})

     begin
        DB.execute("INSERT INTO page_to_person(cid, page_id, pid, role) VALUES(:cid, :page_id, :pid, :role)",
       "cid"=>$current_cid,
       "page_id"=>page_id,
       "pid"=>pid,
       "role"=>"განმცხადებელი")

       #A new person has appeared on a comp data that was scrapped previously
       if $comp_in_db == true
        alrt_bd = Hash.new
        alrt_bd["cid"] = $current_cid
        alrt_bd["pid"] = pid
        alrt_bd["role"] = "განმცხადებელი"
        alert(1, alrt_bd)
       end
       puts "A person pid = #{pid} linked to company cid = #{$current_cid} as განმცხადებელი (Applicant)"
     rescue SQLite3::Exception => e
        puts "Exception occured"
        puts e
     end
   end
   
  if page_data["წარმომადგენელი"] != nil
     pid = insert_person(page_data["წარმომადგენელი"])
     pg_prsn_ls.push({pid,"წარმომადგენელი"})
     begin
        DB.execute("INSERT INTO page_to_person(cid, page_id, pid, role) VALUES(:cid, :page_id, :pid, :role)",
       "cid"=>$current_cid,
       "page_id"=>page_id,
       "pid"=>pid,
       "role"=>"წარმომადგენელი")

       #A new person has appeared on a comp data that was scrapped previously
       if $comp_in_db == true
        alrt_bd = Hash.new
        alrt_bd["cid"] = $current_cid
        alrt_bd["pid"] = pid
        alrt_bd["role"] = "წარმომადგენელი"
        alert(1, alrt_bd)
       end
        puts "A person pid = #{pid} linked to company cid = #{$current_cid} as წარმომადგენელი (Representative)"
     rescue SQLite3::Exception => e
        puts "Exception occured"
        puts e
     end
   end
   
   if page_data["წარმომდგენი"] != nil
     pid = insert_person(page_data["წარმომდგენი"])
     pg_prsn_ls.push({pid, "წარმომდგენი"})
     begin
        DB.execute("INSERT INTO page_to_person(cid, page_id, pid, role) VALUES(:cid, :page_id, :pid, :role)",
       "cid"=>$current_cid,
       "page_id"=>page_id,
       "pid"=>pid,
       "role"=>"წარმომდგენი")

       #A new person has appeared on a comp data that was scrapped previously
       if $comp_in_db == true
        alrt_bd = Hash.new
        alrt_bd["cid"] = $current_cid
        alrt_bd["pid"] = pid
        alrt_bd["role"] = "წარმომდგენი"
        alert(1, alrt_bd)
       end
        puts "A person pid = #{pid} linked to company cid = #{$current_cid} as წარმომდგენი (Presenting)"
     rescue SQLite3::Exception => e
        puts "Exception occured"
        puts e
     end
   end

   #scraping all scan-docs from the page3
   Nokogiri::HTML(pg3.body).xpath(".//div[@id='tabs-3']/div/table[caption[text() = 'სკანირებული დოკუმენტები']]/tr").each{|tr|
    scols = tr.xpath("td")
    s_date = s_text(scols[1].xpath("./span[2]"))
    s_link = attributes(scols[0].xpath("./a"),"href")
    s_fname = scols[2].xpath("./a").text()
    #puts "INFO ADD PAGE comp = #{$current_cid} link = #{s_link} fname = #{s_fname}; date = #{s_date}"
    if s_link != nil
      scan_id = insert_scan(s_link, nil, s_fname)
      scan_list.push(scan_id)
    end
  }

  #scraping all application/status files from the page3
  Nokogiri::HTML(pg3.body).xpath(".//div[@id='tabs-3']/div/table[caption[text() = 'სტატუსი / გადაწყვეტილება']]/tr").each{|tr|
    acols = tr.xpath("td")
    a_date = s_text(acols[1].xpath("./span[@class = 'smalltxt']"))
    a_link = attributes(acols[0].xpath("./a"),"href")
    a_fname = s_text(acols[1].xpath("./span[@class = 'maintxt']"))
    a_status = s_text(acols[2].xpath("./span"))
    #puts "INFO App/status PAGE comp = #{$current_cid} link = #{a_link} fname = #{a_fname}; date = #{a_date}; status = #{a_status}"

    if a_link != nil
      app_list.push(a_link)
      stm = DB.prepare("SELECT * FROM app_status WHERE link = ?")
      stm.bind_params(a_link)
      result = stm.execute
      if result.next()==nil
        max_aid = DB.execute("SELECT MAX(aid) FROM app_status")
        new_aid = Integer(max_aid[0][0]) + 1
        DB.execute("INSERT INTO app_status(aid, cid, date, file_name, status, link, scrap_date)
               VALUES(:aid, :cid, :date, :file_name, :status, :link, :scrap_date)",
        "aid"=>new_aid,
        "cid"=>$current_cid,
        "date"=>a_date,
        "file_name"=>a_fname,
        "status"=>a_status,
        "link"=>a_link,
        "scrap_date"=>Time.now.utc.iso8601)
        if $comp_in_db == true
          alrt_bd = Hash.new
          alrt_bd["cid"] = $current_cid
          alrt_bd["aid"] = new_aid
          alert(2, alrt_bd)
        end
      else
        puts "The application already in the database!"
        result.reset()
        result.each do |row|
          if row[1] != $current_cid or
              row[2] != a_date or
              row[3] != a_fname or
              row[4] != a_status
            puts "Application is distinct!"
            puts "CID: DB=> #{row[1]} || scrapped=> #{$current_cid}"
            puts "Application Date: DB=> #{row[2]} || scrapped=> #{a_date}"
            puts "File Name: DB=> #{row[3]} || scrapped=> #{a_fname}"
            puts "Status: DB=> #{row[4]} || scrapped=> #{a_status}"
          else
            puts "Same Acapplication"
          end
        end
      end
    end
  }
  
 #here the field that are in database but were not encountered during subsequent scraps will be handled
end



def insert_page(page_data)
  max_pg_id = DB.execute("SELECT MAX(page_id) FROM pages")
  new_page_id = Integer(max_pg_id[0][0]) + 1
   stm = DB.prepare("SELECT * FROM PAGES WHERE B_number = '#{page_data["b_number"]}'")
   result = stm.execute
   if result.next() == nil
     #issue an alert if the information is added to a company that was scrapped before
     if $comp_in_db == true
       alrt_bd = Hash.new
       alrt_bd["cid"] = $current_cid
       alrt_bd["page_id"] = new_page_id
       alert(5, alrt_bd)
     end
     DB.execute("INSERT INTO pages(cid, page_id, property_num, B_number, entity_name,
          legal_form, reorg_type, number_of, replacement_info, attached_docs, backed_docs, notes)
          VALUES (:cid, :page_id, :property_num, :B_number, :entity_name, :legal_form,
          :reorg_type, :number_of, :replacement_info, :attached_docs, :backed_docs, :notes)",
          "cid" => $current_cid,
          "page_id" => new_page_id,
          "property_num"=> page_data["property_num"],
          "B_number"=> page_data["b_number"],
          "entity_name"=>page_data["სუბიექტის დასახელება"],
          "legal_form"=>page_data["სამართლებრივი ფორმა"],
          "reorg_type" => page_data["რეორგანიზაციის ტიპი"] ,
          "number_of"=> page_data["რაოდენობა"],
          "replacement_info"=>page_data["შესაცვლელი რეკვიზიტი:"],
          "attached_docs"=>page_data["თანდართული დოკუმენტაცია"],
          "backed_docs"=>page_data["გასაცემი დოკუმენტები"],
          "notes"=>page_data["შენიშვნა"])
          return_value = new_page_id
   else
      result.reset()
      result.each do |row|
        return_value = row[1]
        if row[0] != $current_cid or
              row[2] != page_data["property_num"] or
              row[3] != page_data["b_number"] or
              row[4] != page_data["სუბიექტის დასახელება"] or
              row[5] != page_data["სამართლებრივი ფორმა"] or
              row[6] != page_data["რეორგანიზაციის ტიპი"] or
              row[7] != page_data["რაოდენობა"] or
              row[8] != page_data["შესაცვლელი რეკვიზიტი:"] or
              row[9] != page_data["თანდართული დოკუმენტაცია"] or
              row[10] != page_data["გასაცემი დოკუმენტები"] or
              row[11] != page_data["შენიშვნა"]

        puts "CID"
        puts row[0]
        puts $current_cid
        puts "--------------------------------"
        puts row[2]+"!="+ page_data["property_num"]
        puts row[3]+"!="+ page_data["b_number"]

        puts row[4]
        puts page_data["სუბიექტის დასახელება"]
        puts "--------------------------------"
        puts row[5]
        puts page_data["სამართლებრივი ფორმა"]
        puts "--------------------------------"
        puts row[6]
        puts page_data["რეორგანიზაციის ტიპი"]
        puts "--------------------------------"
        puts row[7]
        puts page_data["რაოდენობა"]
        puts "--------------------------------"
        puts row[8]
        puts page_data["შესაცვლელი რეკვიზიტი:"]
        puts "--------------------------------"
        puts row[9]
        puts page_data["თანდართული დოკუმენტაცია"]
        puts "--------------------------------"
        puts row[10]
        puts page_data["გასაცემი დოკუმენტები"]
        puts "--------------------------------"
        puts row[11]
        puts page_data["შენიშვნა"]
        puts "<<<<<<<<<<<<<<<<page ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        puts "<<<<<<<<<<<<<<<<page UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        else
          puts "SAME PAGE -------------------------->"
        end
      end
   end
   return return_value
end

#insert info about company to the database
#verify if company already in the database(check id_code, p_code, state_reg_code)
#if it is in db verify whether anything different, if different alert, else insert
def insert_comp(data)
  max_row = DB.execute("SELECT MAX(cid) FROM company")
  new_cid = Integer(max_row[0][0]) + 1

  query_qr = "SELECT * FROM COMPANY WHERE "

  #critical section some companies lack all of above fields to be revised for update!! TODO
  if data["საიდენტიფიკაციო კოდი"]== nil and data["პირადი ნომერი"]== nil
      puts "The company (name = #{data["დასახელება"]}) missing both id numbers, quering w/r to company name and reg. date."
      slct = DB.prepare("SELECT * FROM company WHERE comp_name = ? AND state_reg_date = ?")
      slct.bind_params(data["დასახელება"], data["სახელმწიფო რეგისტრაციის თარიღი"])
      rslt = slct.execute
      rslt.reset()
      if rslt.next() != nil
        rslt.reset()
        puts "The company is in the database, verifying the columns"
        $comp_in_db = true
        rslt.each do |row|
          $current_cid = Integer(row[0])
          if row[1] != data["საიდენტიფიკაციო კოდი"] or
                 row[2] != data["პირადი ნომერი"] or
                 row[3] != data["სახელმწიფო რეგისტრაციის ნომერი"] or
                 row[4] != data["დასახელება"] or
                 row[5] != data["სამართლებრივი ფორმა"] or
                 row[6] != data["სახელმწიფო რეგისტრაციის თარიღი"] or
                 row[7] != data["სტატუსი"]

               puts  "Identification Code: DB=> #{row[1]} || scrapped=> #{data["საიდენტიფიკაციო კოდი"]}"
               puts  "P number: DB=> #{row[2]} || scrapped=> #{data["პირადი ნომერი"]}"
               puts  "State registration number: DB=> #{row[3]} || scrapped=> #{data["სახელმწიფო რეგისტრაციის ნომერი"]}"
               puts  "Name: DB=> #{row[4]} || scrapped=> #{data["დასახელება"]}"
               puts  "Legal form: DB=> #{row[5]} || scrapped=> #{data["სამართლებრივი ფორმა"]}"
               puts  "State reg date: DB=>#{row[6]} || scrapped=> #{data["სახელმწიფო რეგისტრაციის თარიღი"]}"
               puts  "Satus: DB=> #{row[7]} || scrapped=> #{data["სტატუსი"]}"
               puts "<<<<<<<<<<<<<<<<critical company ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
               puts "<<<<<<<<<<<<<<<<critical company UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
          else
           puts "<<<<<<<<<<<<<<<<< SAME CRITICAL COMPANY>>>>>>>>>>>>>>>>>>>>>"
          end
        end
      else
        $current_cid = new_cid
        $comp_in_db = false
        DB.execute("INSERT INTO company(cid, id_code, p_code, state_reg_code, comp_name, legal_form, state_reg_date, status, scrap_date) VALUES (
        :cid, :id_code, :p_code, :state_reg_code, :comp_name, :legal_form, :state_reg_date, :status, :scrap_date)",
          "cid" => $current_cid,
          "id_code"=>data["საიდენტიფიკაციო კოდი"],
          "p_code"=>data["პირადი ნომერი"],
          "state_reg_code"=>data["სახელმწიფო რეგისტრაციის ნომერი"],
          "comp_name"=>data["დასახელება"],
          "legal_form"=>data["სამართლებრივი ფორმა"],
          "state_reg_date"=>data["სახელმწიფო რეგისტრაციის თარიღი"],
          "status"=>data["სტატუსი"],
          "scrap_date"=> Time.now.utc.iso8601)

      puts "<--------------------------A company inserted--------------------------->"
      puts "CID = #{$current_cid}; ID=#{data["საიდენტიფიკაციო კოდი"]}; P_code=#{data["პირადი ნომერი"]}; State_reg_code=#{data["სახელმწიფო რეგისტრაციის ნომერი"]}"
      puts "Company name: #{data["დასახელება"]}"
      puts "legal form: #{data["სამართლებრივი ფორმა"]}; state_reg_date=#{data["სახელმწიფო რეგისტრაციის თარიღი"]} status:#{data["სტატუსი"]}"
      puts "Scrape date: #{Time.now.utc.iso8601}"
      puts "<----------------------------------------------------------------------->"

      end
      return
  end



  if data["საიდენტიფიკაციო კოდი"] != nil
    query_qr = query_qr + " id_code = '#{data["საიდენტიფიკაციო კოდი"]}' "
    id_added = true
    valid_query = true
  end
  if data["პირადი ნომერი"] != nil
    if id_added == true
      query_qr = query_qr + " OR "
    end
    query_qr = query_qr + " p_code = '#{data["პირადი ნომერი"]}' "
    pcode_added = true
    valid_query = true
  end

  if valid_query
    statement = DB.prepare(query_qr)
    result = statement.execute
    if result.next() == nil
      $current_cid = new_cid
      $comp_in_db = false
      DB.execute("INSERT INTO company(cid, id_code, p_code, state_reg_code, comp_name, legal_form, state_reg_date, status, scrap_date) VALUES (
      :cid, :id_code, :p_code, :state_reg_code, :comp_name, :legal_form, :state_reg_date, :status, :scrap_date)",
        "cid" => $current_cid,
        "id_code"=>data["საიდენტიფიკაციო კოდი"],
        "p_code"=>data["პირადი ნომერი"],
        "state_reg_code"=>data["სახელმწიფო რეგისტრაციის ნომერი"],
        "comp_name"=>data["დასახელება"],
        "legal_form"=>data["სამართლებრივი ფორმა"],
        "state_reg_date"=>data["სახელმწიფო რეგისტრაციის თარიღი"],
        "status"=>data["სტატუსი"],
        "scrap_date"=> Time.now.utc.iso8601)
      
      puts "<--------------------------A company inserted--------------------------->"
      puts "CID = #{$current_cid}; ID=#{data["საიდენტიფიკაციო კოდი"]}; P_code=#{data["პირადი ნომერი"]}; State_reg_code=#{data["სახელმწიფო რეგისტრაციის ნომერი"]}"
      puts "Company name: #{data["დასახელება"]}"
      puts "legal form: #{data["სამართლებრივი ფორმა"]}; state_reg_date=#{data["სახელმწიფო რეგისტრაციის თარიღი"]} status:#{data["სტატუსი"]}"
      puts "Scrape date: #{Time.now.utc.iso8601}"
      puts "<----------------------------------------------------------------------->"
    else
      $comp_in_db = true
      result.reset()
      result.each do |row|
        $current_cid = Integer(row[0])
         if row[1] != data["საიდენტიფიკაციო კოდი"] or #Identification Code
             row[2] != data["პირადი ნომერი"] or #P number
             row[3] != data["სახელმწიფო რეგისტრაციის ნომერი"] or #state registration number
             row[4] != data["დასახელება"] or #name
             row[5] != data["სამართლებრივი ფორმა"] or #Legal Form
             row[6] != data["სახელმწიფო რეგისტრაციის თარიღი"] or #State registration date
             row[7] != data["სტატუსი"] #status

             puts  "Identification Code: DB=> #{row[1]} || scrapped=> #{data["საიდენტიფიკაციო კოდი"]}"
             puts  "P number: DB=> #{row[2]} || scrapped=> #{data["პირადი ნომერი"]}"
             puts  "State registration number: DB=> #{row[3]} || scrapped=> #{data["სახელმწიფო რეგისტრაციის ნომერი"]}"
             puts  "Name: DB=>#{row[4]} || scrapped=> #{data["დასახელება"]}"
             puts  "Legal Form:  DB=> #{row[5]} || scrapped=> #{data["სამართლებრივი ფორმა"]}"
             puts  "State registration date: DB=> #{row[6]} || scrapped=> #{data["სახელმწიფო რეგისტრაციის თარიღი"]}"
             puts  "Status: DB=> #{row[7]} || scrapped=> #{data["სტატუსი"]}"

           puts "<<<<<<<<<<<<<<<<company ALERT!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
           puts "<<<<<<<<<<<<<<<<company UPDATE!>>>>>>>>>>>>>>>>>>>>>>>>>>>"
         else
           puts "<<<<<<<<<<<<<<<<<SAME company>>>>>>>>>>>>>>>>>>>>>>>>"
         end
      end
    end
  end
end
  
def insert_person(data_line)
  data_line = data_line.gsub(/\n/, ' ')
  name = data_line.split(/.*/,1).last.gsub(/\s[(].*/, '')
  if data_line.include? "(კოდი:"
    #company acts like a person
    p_n = data_line.split(/.*(კოდი:)/,2).last.gsub(/[)].*/, '')
  else
    p_n = data_line.split(/.*(\(პ\/ნ:)/,2).last.gsub(/[)].*/, '')
  end
  p_n = p_n.gsub(' ', '')
  address = data_line.split(/.*/,1).last.gsub(/.*[)]/, '')
  slct = DB.prepare("SELECT * FROM people WHERE personal_number = ?")
  slct.bind_params(p_n)
  rslt = slct.execute
  max_row = DB.execute("SELECT MAX(pid) FROM people")
  new_pid = Integer(max_row[0][0]) + 1
  if rslt.next() == nil
    DB.execute("INSERT INTO people(pid, name, address, personal_number) VALUES(:pid, :name, :address, :personal_number)",
      "pid"=>new_pid,
      "name"=>name,
      "address"=>address,
      "personal_number"=>p_n)
      pid = new_pid
      puts "A person inserted to DB: PID=#{new_pid}; name=#{name}; P/N = #{p_n}; address=#{address}"
  else
    puts "THE P/N IS ALREADY in the DATABASE"
    rslt.reset()
    rslt.each do |row|
     pid = Integer(row[0])
     db_name = row[1]
     db_address = row[2]
     db_pn = row[3]
     if db_address == nil
       DB.execute("UPDATE people SET address= :address WHERE personal_number = :pn",
       "address"=> address,
       "pn"=>p_n)
       puts "THE ADDRESS OF THE PERSON IS UPDATED TO: #{address}"
     end
     puts "Inserting: PID=#{new_pid}; name=#{name}; P/N = #{p_n}; address=#{address}"
     puts "In the DB: PID=#{pid}; name=#{db_name}; P/N = #{db_pn}; address=#{db_address}"

    end
  end
 return pid
end

def extract_person(pn, name, relation, ext_id)
  slct = DB.prepare("SELECT * FROM people WHERE personal_number = ?")
  slct.bind_params(pn)
  rslt = slct.execute
  if rslt.next() == nil
    max_row = DB.execute("SELECT MAX(pid) FROM people")
    new_pid = Integer(max_row[0][0]) + 1
    DB.execute("INSERT INTO people(pid, name, personal_number) VALUES(:pid, :name, :personal_number)",
      "pid"=>new_pid,
      "name"=>name,
      "personal_number"=>pn)
      pid = new_pid
      puts "A person inserted to DB from an extract: PID=#{new_pid}; name=#{name}; P/N = #{pn};"
  else
    puts "THE P/N FROM AN EXTRACT IS ALREADY in the DATABASE "
    rslt.reset()
    rslt.each do |row|
     pid = Integer(row[0])
     db_name = row[1]
     db_pn = row[3]
     puts "Inserting: PID=#{new_pid}; name=#{name}; P/N = #{pn};"
     puts "In the DB: PID=#{pid}; name=#{db_name}; P/N = #{db_pn};"
    end
  end

  begin
    DB.execute("INSERT INTO person_to_extract(cid, eid, pid, role) VAlUES(:cid, :eid, :pid, :role)",
      "cid"=>$current_cid,
      "eid"=>ext_id,
      "pid"=>pid,
      "role"=>relation)
    if $comp_in_db == true
      alrt_bd = Hash.new
      alrt_bd["cid"] = $current_cid
      alrt_bd["eid"] = ext_id
      alrt_bd["pid"] = pid
      alert(6, alrt_bd)
    end
  rescue SQLite3::Exception => e
      puts "Exception occured"
      puts e
   end
end


def get_application(link)
  doc_id = CGI.parse(link)['doc_id']
  app_id = CGI.parse(link)['app_id']
  puts "doc_id = #{doc_id}"
  puts "app id = #{app_id}"
  ext_param = {"c"=>"app","m"=>"show_doc", "doc_id"=>doc_id, "app_id"=>app_id}
    app_page = nil
    begin
      begin
       Timeout::timeout(5) {
       app_page = @br.post(BASE_URL + "/main.php",ext_param,HDR)
      }
      rescue Timeout::Error
        puts 'get_application() (pg3) took too long, trying again...'
        begin
              #ping google, break if internet connection is active
              break if Ping.pingecho("google.com",10,80)
              puts "waiting for ping google.com..."
              sleep 2
        end while(true)
        get_application(link)
      end
   rescue Exception => exc
     #in case of some server related problems the program waits for 5 sec and resubmits the data
      puts "ERROR: #{exc.message} in get_add() pg3! Trying again in 5 seconds."
      sleep 5
      get_application(link)
   end
   puts app_page.body
end

def alert(code, body)
  puts "<<<<<<<<<<<<<<<<<<<<<<<ALERT ALERT ALERT>>>>>>>>>>>>>>>>>>>>>>>>>>>"
  puts code
  puts body
end

action()