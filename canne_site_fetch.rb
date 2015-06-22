require 'open-uri'
require 'nokogiri'
require 'parallel'
require 'fileutils'
require 'RMagick'
include Magick
require 'logger'
require 'mechanize'
log = Logger.new("new_log.txt")

# require 'bundler'
# Bundler.require

#リストを作って、URLを取り出す。
def download_media(html, info, log)
  html.css("video > source, audio").each do |sourcetag|
    media_uri = sourcetag["src"].to_s
    retry_count = 0
    begin
      filename = File.basename(media_uri).gsub(/\?.*/, "")
      File.open(filename, "w") do |file|
        open(media_uri) do |data|
          file.write(data.read)
        end
      end
    rescue OpenURI::HTTPError => e
      if retry_count < 2
        retry_count += 1
        log.info "RETRY: msg:#{e.message}: uri:#{media_uri}, dir:#{info["name"]}"
        e.io.close
        retry
      end
      log.error "#{e.message}: uri:#{media_uri}, dir:#{info["name"]}"
      e.io.close
    end
  end
end

def download_image(html, info, log,agent)

  if html.css("ol.carousel__thumbnails > li > a") && html.css("ol.carousel__thumbnails > li > a")[0]
    image_url = "http://www.canneslionsarchive.com" + html.css("ol.carousel__thumbnails > li > a")[0].attribute("href").value
    p image_url
    agent.get(image_url) do |page|
      html = Nokogiri::HTML(page.body)
    end
    count = 0
    html.css("script").each do |script|
      count = count + 1
      if script.attribute("src") && script.attribute("src").value == "//cdn.filespin.io/zoomable/openseadragon.min.js"
        p "ある"
        return
      end
    end
  else
    p "ない"
    return
  end
  # return
  script = html.css("script")[count]
# html.css("div.seadragon-container + script").each do |script|
  deepzoom = {}
  deepzoom["xmlpath"]  = /http:\/\/.+\.xml/.match(script.text).to_s
  p deepzoom["xmlpath"]
  deepzoom["directory"] = /^.*\//.match(deepzoom["xmlpath"]).to_s
  deepzoom["xml"]      = Nokogiri::XML(open(deepzoom["xmlpath"]))
  File.open("deepzoom.xml", "w") do |file|
    file.puts deepzoom["xml"].to_xml
  end
  deepzoom["format"]   = deepzoom["xml"].css("Image").first["Format"].to_s
  deepzoom["overlap"]  = deepzoom["xml"].css("Image").first["Overlap"].to_i
  deepzoom["tilesize"] = deepzoom["xml"].css("Image").first["TileSize"].to_i
  deepzoom["height"]   = deepzoom["xml"].css("Size").first["Height"].to_i
  deepzoom["width"]    = deepzoom["xml"].css("Size").first["Width"].to_i

  FileUtils.mkdir("deepzoom_files") unless FileTest.exist?("deepzoom_files")
  Dir.chdir("deepzoom_files") do
    img_list = create_image_list(deepzoom, info, log)
    download_image_list(img_list, info, log)
    composite_images(deepzoom)
  end

  # end
end

def download_image_list(img_list, info, log)
  Parallel.map(img_list, :in_threads => 10) { |uri|
    filename = File.basename(uri)
    retry_count = 0
    begin
      File.open(filename, "w") do |file|
        open(uri) do |data|
          file.write(data.read)
        end
      end
    rescue OpenURI::HTTPError => e
      if retry_count < 2
        retry_count += 1
        log.info "RETRY: msg:#{e.message}: uri:#{uri}, dir:#{info["name"]}"
        e.io.close
        retry
      end
      log.error "#{e.message}: uri:#{uri}, dir:#{info["name"]}"
      e.io.close
    end
  }
end


def composite_images(deepzoom)
  w_count = (deepzoom["width"].to_f  / deepzoom["tilesize"]).ceil
  h_count = (deepzoom["height"].to_f / deepzoom["tilesize"]).ceil
  last_img = Magick::ImageList.new("#{w_count-1}_#{h_count-1}.#{deepzoom['format']}")
  last_width = last_img.columns.to_i
  last_img.destroy!

  for w in 0..w_count-1 do
    tmp_width = 0
    if w == 0
      tmp_width = deepzoom["tilesize"] + deepzoom["overlap"]
    elsif w == w_count-1
      tmp_width = last_width
    else
      tmp_width = deepzoom["tilesize"] + deepzoom["overlap"]*2
    end
    tmp = Image.new(tmp_width, deepzoom["height"])
    for h in 0..h_count-1 do
      if h != 0 and h % 20 == 0
        tmp.write("tmp#{w}.png")
        tmp.destroy!
        call_gc()
        tmp = Image.from_blob(File.read("tmp#{w}.png")).shift
      end
      img = Image.from_blob(File.read("#{w}_#{h}.#{deepzoom['format']}")).shift
      if h == 0
        tmp = tmp.composite(img, 0, 0, OverCompositeOp)
      else
        tmp = tmp.composite(img, 0, deepzoom["tilesize"]*h - deepzoom["overlap"], OverCompositeOp)
      end
    end
    tmp.write("tmp#{w}.png")

    tmp.destroy!
    call_gc()
  end

  result = Image.new(deepzoom["width"], deepzoom["height"])
  for w in 0..w_count-1 do
    img = Image.from_blob(File.read("tmp#{w}.png")).shift
    if w == 0
      result = result.composite(img, 0, 0, OverCompositeOp)
    else
      result = result.composite(img, deepzoom["tilesize"]*w - deepzoom["overlap"], 0, OverCompositeOp)
    end
    if w != 0 and w % 20 == 0
      result.write("tmp.png")
      result.destroy!
      call_gc()
      result = Image.from_blob(File.read("tmp.png")).shift
    end
  end

  if deepzoom["format"] == "jpg"
    result.write("../board.jpg") { self.quality = 85 }
  else
    result.write("../board.png")
  end

  result.destroy!
  call_gc()
end


def call_gc
  fDisabled = GC.enable
  GC.start
  GC.disable if fDisabled
end


def create_image_list(deepzoom, info, log)
  # detect max zoom value
  zoom = 18
  retry_count = 0
  test_uri = ""
  begin
    test_uri = "#{deepzoom['directory']}deepzoom_files/#{zoom}/0_0.jpg"
    test_img = open(test_uri)
  rescue
    if retry_count < 1
      retry_count += 1
      retry
    end
    zoom -= 1
    retry unless zoom < 10
  end

  # create img_url list
  img_list = []
  for w in 0..(deepzoom["width"].to_f / deepzoom["tilesize"]).ceil-1 do
    for h in 0..(deepzoom["height"].to_f / deepzoom["tilesize"]).ceil-1 do
      img_list.push "#{deepzoom['directory']}deepzoom_files/#{zoom}/#{w}_#{h}.jpg"
    end
  end
  return img_list
end

agent = Mechanize.new
agent.read_timeout = 120

#Tony Williams tonytony@gmail.com
agent.get('http://www.canneslionsarchive.com/winners/results/outdoor') do |page|
    # ログインする
    agent.page.form(:action => '/Login/GetStartedGuestLogin'){|form|
        form.field_with(:name => 'Name').value = 'Tony Williams'
        form.field_with(:name => 'EmailAddress').value = 'tonytony@gmail.com'
        # フォームに備え付けの送信ボタンをクリック
        form.click_button
    }
end

# url = "http://www.canneslionsarchive.com/winners/results/outdoor"
workspace = ARGV[0].to_s.gsub(/\W/, '_')
FileUtils.mkdir(workspace) unless FileTest.exist?(workspace)
Dir.chdir(workspace)

#リストを取り出す。
list = []
agent.get(ARGV[0]) do |page|

  html = Nokogiri::HTML(page.body)
  list += html.css("ul.results-list > li >  a").map {|atag| "http://www.canneslionsarchive.com" + atag['href']}

end

#時間を3秒遅らせる。
sleep 3

list.each { |uri|
  agent.get(uri) do |page|

      html = Nokogiri::HTML(page.body)
      # p html
      info = {}
      info["title"] = html.css("h1.view-header__title").text
      p info["title"]
      info["prize"] = html.css("p.award-type").text
      p info["prize"]
      info["category"] = html.css("h2.entry__summary__category").text
      p info["category"]
      info["name"] = "[#{info['prize']}] #{info['title'].gsub(/\W/, '_')} - #{info['category'].gsub(/\W/, '_')}"
      p info["name"]

      FileUtils.mkdir(info["name"]) unless FileTest.exist?(info["name"])
      Dir.chdir(info["name"]) do
        File.open("#{info['name']}.original.html", "w") do |file|
            file.puts html.to_html
        end

          # download_media(html, info, log)
          # download_image(html, info, log,agent)

          log.info "finished: #{info['name']}"
      end
      sleep 5
      p "一つのサイトダウンロードした。"
  end
}
