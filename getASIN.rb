require 'open-uri'
require 'nokogiri'
require 'anemone'
require 'uri'
require 'mechanize'

def getTopURL(pNames)
	urls = Hash.new
	pNames.each do |pName|
		urls[pName] = URI.escape("http://www.amazon.co.jp/s/ref=nb_sb_noss?__mk_ja_JP=カタカナ&url=search-alias%3Daps&field-keywords=" + pName)
	end

	urls.each do |pName, url|

	end

	pNames.each do |pName|
		puts pName
		page = agent.get(url)
		if page.at("//*[@id='result_0']/div/div[2]/div[1]/a")
			urls[pName] = page.at("//*[@id='result_0']/div/div[2]/div[1]/a")[:href]
		else
			$pList[pName][3] = "検索失敗"
		end
	end
	return urls
end

puts getTopURL(["Macbook","100円でコーラ","初めに読みたい","マインクラフト","マウス"])