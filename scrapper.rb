#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems'
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'json'
require 'logger'
require './libSC.rb'

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
HDR = {"X-Requested-With"=>"XMLHttpRequest","cookie"=>"MMR_PUBLIC=7ip3pu3gh4phbaen4f8kpjoi54"}
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
          #puts "<<<<<<<<<<<<<<<<<<1>>>>>>>>>>>>>>>>>>>>>>>>>>>"
          #puts dummy1
          #puts "<<<<<<<<<<<<<<<<<<2>>>>>>>>>>>>>>>>>>>>>>>>>>>"
          #puts dummy2
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

def get_add(id)
   params3 = {"c"=>"app","m"=>"show_app", "app_id"=> id}
   pg3 = @br.post(BASE_URL + "/main.php",params3,HDR)
   
   Nokogiri::HTML(pg3.body).xpath(".//div[@id='tabs-3']/div/table[caption[text() = 'მომზადებული დოკუმენტები']]/tr").each{|tr|
    rows = tr.xpath('td')
    if(rows.length < 3)
      puts rows
      next
    end
    link = attributes(rows[0].xpath("./a"),"href")
    dummy = rows[1].xpath("./span")
    text = s_text(dummy[0].xpath("text()"))
    extract_date = s_text(dummy[1].xpath("text()"))
    puts link + "**" + text + "**" + extract_date
   }

end

action()