#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems'
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'json'
require 'logger'
require './lib/libSC.rb'

#Sole enterpreneur 	1
#SPS 			2
#Cooperative 		3
#LTD			4
#Joint Stock Co.	5
#Society limited	6
#non-profit		7
#Legal entity		10
#Foreign enterprise	26
#Foreign non-profit	27
#Busines Partnership	28		


BASE_URL = "https://enreg.reestri.gov.ge"

@br = Mechanize.new { |b|
  b.user_agent_alias = 'Mac Safari'
  b.read_timeout = 1200
  b.max_history=0
  b.retry_change_requests = true
  b.verify_mode = OpenSSL::SSL::VERIFY_NONE
}

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
   hdr = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
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
	pg2 = @br.post(BASE_URL + "/main.php",params2,hdr)
	Nokogiri::HTML(pg2.body).xpath(".//table[@class='mytbl']/tbody/tr").each{|tr|
		
		td2 = tr.xpath("td")   
		puts td2.length
  		#if td2.length < 6
		#   puts tr.inner_html
        	#   next
      		#end
		#reg_date = td2[12].xpath("./text()")
		#puts td2
	    }
	    puts ":::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
	}
  end
end

def action()

  hdr = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
  params = {"c"=>"search","m"=>"find_legal_persons","s_legal_person_idnumber"=>"","s_legal_person_name"=>"","s_legal_person_form"=>"26"}

  begin
    pg = @br.post(BASE_URL + "/main.php",params,hdr)
    scrape(pg.body,"list",{})
    nex = attributes(Nokogiri::HTML(pg.body).xpath(".//td/a[img[contains(@src,'next.png')]]"),"onclick").scan(/legal_person_paginate\((\d+)\)/).flatten.first    
    break if nex.nil? 
	#break if nex > 5
puts nex
    params = {"c"=>"search","m"=>"find_legal_persons","p"=>nex}
  end while(true)
end

action()