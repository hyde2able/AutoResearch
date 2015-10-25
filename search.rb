require 'capybara'
require 'selenium-webdriver'
require 'capybara/dsl'
require 'capybara/poltergeist'
# Capybaraの設定
Capybara.configure do |config|
	config.run_server = false
	config.current_driver = :poltergeist
	config.javascript_driver = :poltergeist
	config.app_host = "http://www.amazon.co.jp/"
	config.default_wait_time = 5
	config.default_selector = :xpath
end
Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, {
                    js_errors: false,
                    timeout: 1500,
                    phantomjs_options: [
                              '--load-images=no',
                              '--ignore-ssl-errors=yes',
                              '--ssl-protocol=any']})
end
module Crawler
	class Amazon
		include Capybara::DSL
		@@count = 0
		def initialize(pName)
			@pName = pName
			@@count += 1
		end

		#商品名pNameを引数にAmazonで検索してTopの検索結果のページに遷移
		def lookup pName=@pName
			puts "#{pName}を検索中... ( #{@@count * 100 / $count}%が完了 )"
			page.driver.headers = { "User-Agent" => "Mac Chrome" }
			visit URI.escape("http://www.amazon.co.jp/s/ref=nb_sb_noss?__mk_ja_JP=%E3%82%AB%E3%82%BF%E3%82%AB%E3%83%8A&url=search-alias%3Daps&field-keywords=" + pName)
			# もし検索結果が一つもなかった場合 => ASINなどがない。
			if page.has_xpath?("//*[@id='noResultsTitle']") || $pList[pName][1] == "店頭販売"
				$pList[pName][3] = "検索失敗"
				return
			end
			visit find(:xpath, "//*[@id='result_0']/div/div[2]/div[1]/a")[:href]	# 検索TOP商品に遷移
			if page.has_xpath?("/html/body/center/span[@class='alert']")
				$pList[pName][3] = "検索失敗"; $pList[pName][12] = "18禁"
				return
			end
			self.getASIN
		end

		#商品ページに来たので、そのASINと最安値を取得する。
		def getASIN
			return if $pList[@pName][3] == "検索失敗"
			# 新品の最安値を取得
			lowest_price = first("//*[@id='olp_feature_div']/div/span/span")? 
				first("//*[@id='olp_feature_div']/div/span/span").text : 
					(first('//*[@id="priceblock_ourprice"]')? first('//*[@id="priceblock_ourprice"]').text : "0")
			lowest_price.gsub!(/[^\d]/, "").to_i

			print "#{@pName}のASIN取得中..."
			if first('//*[@id="prodDetails"]/div/div[2]/div[1]/div[2]/div/div/table/tbody/tr[1]/td[2]')
				asin = first('//*[@id="prodDetails"]/div/div[2]/div[1]/div[2]/div/div/table').text
			else
				asin = first("//*[@id='detail_bullets_id']/table/tbody/tr/td/div[@class='content']").text
			end
			if asin =~ /([A-Z0-9]{10})/
				asin = $1
			end
			puts asin
			$pList[@pName][3] = asin
			$pList[@pName][4] = lowest_price

			# この時点でAmazonの方が安ければFBAはわざわざ取得しない
			if lowest_price <= $pList[@pName][1]
				$pList[@pName][5] = "SKIP"
				return
			end
			$pList[@pName][5] = "FBA"
			self.getFBA asin,lowest_price
		end

		# FBA料金計算シミューレータにアクセスし、ASINと売値価格を入力して、手数料を取得する
		def getFBA asin,price
			puts "#{@pName}のFBA取得中..."
			visit "https://sellercentral.amazon.co.jp/hz/fba/profitabilitycalculator/index?lang=ja_JP"	# FBAシミューレータのURL
			fill_in "search-string", :with => asin 		# ASINを入力

			begin #その商品がまた売られていなかったら
				find(:xpath, "//*[@id='search-form']/span[1]/span/input").click  # 検索ボタンをクリック
			rescue
				$pList[@pName][3] = "FBA未登録"
				return
			end
			self.wait_for_ajax	# 画面内でajaxで検索をしているのでその間待機する

			if page.has_xpath?("//*[@id='a-popover-2']/div/div[2]/ul/li[1]/button/span")
				first("//*[@id='a-popover-2']/div/div[2]/ul/li[1]/button/span").click
				self.wait_for_ajax
			end

			fill_in "afn-fees-price", :with => price 	# 売値priceを入力
			begin 
				click_button "計算"
			rescue
				page.save_screenshot("error/"+@pName+".png", :full => true)
				return
			end
			self.wait_for_ajax

			#sales_commission = find(:xpath, "//*[@id='afn-fees']/dl/dd[4]/input").value.to_i
			#storage_fee = find(:xpath, "//*[@id='afn-fees']/dl/dd[10]/input").value.to_i
			fee = find(:xpath, "//*[@id='afn-fees']/dl/dd[15]/input").value.to_i * -1
			#predict = find(:xpath, "//*[@id='mfn-units-sold']").value.to_i
			$pList[@pName][6] = fee
		end

		def wait_for_ajax
			Timeout.timeout(Capybara.default_wait_time) do
				loop until page.evaluate_script('jQuery.active').zero?
			end
		end
	end
end

