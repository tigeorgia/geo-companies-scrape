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


BASE_URL = "https://enreg.reestri.gov.ge"
HDR = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
@br = Mechanize.new { |b|
  b.user_agent_alias = 'Mac Safari'
  b.read_timeout = 1200
  b.max_history=0
  b.retry_change_requests = true
  b.verify_mode = OpenSSL::SSL::VERIFY_NONE
}
@gent = Mechanize.new
@gent.pluggable_parser.pdf = Mechanize::FileSaver

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

def scrape(data,act,rec)
    if act == "list"
      records = []
      Nokogiri::HTML(data).xpath(".//table[@class='main_tbl shadow']/tbody/tr").each{|tr|
        td = tr.xpath("td")
        if td.length < 6
          puts tr.inner_html
          next
        end
        cid = attributes(td[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
        i_code = s_text(td[1].xpath("./span/text()"))
        p_code = s_text(td[2].xpath("./span/text()"))
        company_name = s_text(td[3].xpath("./text()"))
        type = s_text(td[4].xpath("./text()"))
        status = s_text(td[5].xpath("./span/text()"))
        link = BASE_URL + "/main.php?c=app&m=show_legal_person&legal_code_id=#{attributes(td[0].xpath('./a'),'onclick').split('(').last.gsub(')','')}"
        scrap_date = Time.now

        params2 = {"c"=>"app","m"=>"show_legal_person", "legal_code_id"=>cid}
        #puts cid
        pg2 = @br.post(BASE_URL + "/main.php",params2,HDR)
        puts i_code
        Nokogiri::HTML(pg2.body).xpath(".//table[@class='mytbl']/tbody/tr").each{|tr|
            td2 = tr.xpath("td")
            #puts td2.length
            if td2.length != 2
              #puts tr.inner_html
              next
            end
            dummy1 = s_text(td2[0].xpath("./text()"))
            dummy2 = s_text(td2[1])
            puts "<<<<<<<<<<<<<<<<<<1>>>>>>>>>>>>>>>>>>>>>>>>>>>"
            puts dummy1
            puts "<<<<<<<<<<<<<<<<<<2>>>>>>>>>>>>>>>>>>>>>>>>>>>"
            puts dummy2
          #reg_date = td2[12].xpath("./text()")
          #puts td2
        }
        Nokogiri::HTML(pg2.body).xpath(".//div[@id='container']/table[caption[text() = 'განცხადებები']]/tbody/tr").each{|tr|
          td3 = tr.xpath("td")
          app_id = attributes(td3[0].xpath("./a"),"onclick").split("(").last.gsub(")","")
          get_add(app_id)
      }
	    puts ":::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
	}
  end
end


def pdf_parser(file)
	receiver = PDF::Reader::RegisterReceiver.new
	filename = File.expand_path(file)
	PDF::Reader.open(filename) do |reader|
	  reader.pages.each do |page|
	    puts page.text
	  end
	end
end

#this method saves the extract once it is called with appropriate id's,
#calls pdf_parser to read/parse the extract and then removes the file
def get_extract(scandoc_id, app_id)
  ext_param = {"c"=>"mortgage","m"=>"get_output_by_id", "scandoc_id"=>scandoc_id, "app_id"=>app_id}
  @gent.post(BASE_URL + "/main.php",ext_param,HDR)
  File.rename("./enreg.reestri.gov.ge/main.php", "./enreg.reestri.gov.ge/temp_extract.pdf")
  pdf_parser("./enreg.reestri.gov.ge/temp_extract.pdf")
  File.delete("./enreg.reestri.gov.ge/temp_extract.pdf")
end


def action()

  params = {"c"=>"search","m"=>"find_legal_persons","s_legal_person_idnumber"=>"","s_legal_person_name"=>"","s_legal_person_form"=>"26"}

  begin
    pg = @br.post(BASE_URL + "/main.php",params,HDR)
    scrape(pg.body,"list",{})
    nex = attributes(Nokogiri::HTML(pg.body).xpath(".//td/a[img[contains(@src,'next.png')]]"),"onclick").scan(/legal_person_paginate\((\d+)\)/).flatten.first
    break if nex.nil?
    #break if nex > 5
    #puts nex
    params = {"c"=>"search","m"=>"find_legal_persons","p"=>nex}
  end while(true)
end

#goes to the last dead-end page and get the info
def get_add(id)
  puts "ID + " + id
   params3 = {"c"=>"app","m"=>"show_app", "app_id"=> id}
   pg3 = @br.post(BASE_URL + "/main.php",params3,HDR)
   
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
    puts link + "**" + text + "**" + extract_date
    
    #check whether the document is djvu file, if true, saves the link to the djvu
    if s_text(rows[2]).end_with?(".djvu")
      puts "DEJA VU!!"
      next
    end
    get_extract(scandoc_id, app_id)
   }

end

action()