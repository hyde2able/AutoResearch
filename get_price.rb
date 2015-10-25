=begin
	ヨドバシのサイトから商品名をスクレイピングして、そのASINをAmazonサイトで検索してマッチさせる。
	その結果から、Amazonでの最安値で売ると仮定して、FBAを算出する
=end
	
require 'open-uri'
require 'nokogiri'
require 'anemone'
require 'uri'
require 'capybara'
require 'parallel'
require 'thread'
require 'selenium-webdriver'
require 'capybara/dsl'
require 'capybara/poltergeist'
require './category.rb' #ヨドバシのサイトのカテゴリー別のurlを返す関数など
require './search.rb'

$pList = Hash.new()
# ここに結果を格納していく。形式は $pList[商品名] = [商品名,価格(ヨドバシ),ポイント,ASIN,新品最安値(Amazon),販売手数料,月間保管手数料,合計手数料,月間予想販売数,予想利益,利益率,粗利益]

################################ ベースURL(url)と件数(count)と設定　から商品名と値段、ポイントを取得 ########################################################
class Parse
	attr_accessor :url, :count, :opts
	def initialize(url, count, opts={:obey_robots_txt => true, :depth_limit => 1})
		@url = url
		@count = count
		@opts = opts
	end

	#指定されたpageをスクレイピングして商品名、価格、ポイントを取得する
	def scraping(page)
		page.doc.xpath("//div[@id='spt_hznList']/div[@class='pListBlock hznBox']").each do |node|
			node = node.xpath("div[@class='inner']")
			pName = node.xpath("a/div[@class='pImg']/img").attr("alt").to_s
			pPrice = node.xpath("div[@class='pInfo']/ul/li[1]/strong[@class='red']/text()").to_s
			pPoint = node.xpath("div[@class='pInfo']/ul/li[2]/span[@class='orange']/text()").to_s
			pPrice = "店頭販売" if pPrice.empty?

			pPoint.sub!(/(.*?)/, "")
			pPrice.gsub!(/[^\d]/, "").to_i
			pPoint.gsub!(/[^\d]/, "").to_i
			$pList[pName] = Array.new(11){ String.new }
			$pList[pName][0..2] = [pName, pPrice, pPoint]

			@count -= 1
			break if @count <= 0
		end
	end

	# ベースのURLから次のページをクロールしてスクレイピングするサイトpageをgetメソッドに送る
	def crawl(url=@url, opts=@opts)
		Anemone.crawl(url, opts) do |anemone|
			anemone.focus_crawl do |page|
				page.links.keep_if{ |link|
					link.to_s.match(/#{url}\?count=24&disptyp=02&page=\d{,2}&searchtarget=prodname&sorttyp=COINCIDENCE_RANKING$/)
				}
			end
			anemone.on_every_page do |page|
				self.scraping page
			end
		end
	end
end
################################ $pListに関するコード ########################################################
# 結果を出力する
def output filename="sample.csv"
	File.open(filename, "w") do |f|
		f.puts "商品名,仕入元値,割引値(ポイント),ASIN,新品最安値(Amazon),FBA/SKIP,手数料,予想利益,利益率,粗利益率,その他"
		$pList.each do |pName, details|
			details.each do |detail|
				f.print detail.to_s + ","
			end
			f.puts
		end
	end
	puts "#{filename}に書き出し完了"
end

# pListの商品名からASINを
def search
	filename = "results/" + DateTime.now.strftime('%Y%m%d%H%M%S') + ".csv"
	#Parallel.map($pList, :in_threads => 2) do |pName, details|
	count = 0
	$pList.each do |pName, details|
		Crawler::Amazon.new(pName).lookup
		count += 1
		if count % 5 == 0
			calculate
			output filename
		end
	end
	calculate
	output filename
end

# データから利益率などを計算
def calculate
	$pList.each do |pName, details|
		next if details[3] == "検索失敗" || details[3] == "FBA未登録" || details[5] == "SKIP"
		$pList[pName][7] = details[4].to_i - details[1].to_i - details[6].to_i 		# Amazon - 仕入値 - 手数料
		$pList[pName][8] = $pList[pName][7].to_f / details[4].to_f * 100.0 if details[4].to_f != 0
		$pList[pName][9] = $pList[pName][7] / details[1].to_f * 100.0 if details[1].to_f != 0
	end
end

################################# 実際の実行コード  #######################################################
start = Time.now
url = ARGV[0] || yodobashi("家電","調理")
$count = ARGV[1] || 150
p = Parse.new(url, $count )
# 50件で 530s かかってしまう。並列処理で早くなるか？
p.crawl
p "#{Time.now- start}sで#{$count}件のデータ取得完了"
search
p "#{Time.now-start}sで#{$count}件の解析完了"


