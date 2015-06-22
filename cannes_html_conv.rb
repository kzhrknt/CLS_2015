require 'nokogiri'

def conv_html(html)
	title = html.css(".win_title").first.text.to_s
	win_heading = html.css(".win_heading").first
	tables = html.css("table")

	return <<-EOS
<!doctype html>
<head>
	<title>#{title}</title>
	<meta charset="UTF-8" />
	<meta name="viewport" content="width=516" />
	<style type="text/css" rel="stylesheet">body{margin:8px;font-family:HelveticaNeue-Light,"Helvetica Neue Light","Helvetica Neue",Helvetica,Arial,"Lucida Grande",sans-serif;font-weight:300;line-height:1.231;color:#333;font-size:13px;letter-spacing:1px}.wrapper{width:500px}.heading_prize{float:right;padding:5px 20px;margin-left:15px;text-align:center;font-family:"AvantGardeGothicITCW01B 731063";text-transform:uppercase;font-weight:400}.list_prize_gp{color:#000;background:#F8DC2E -webkit-linear-gradient(top,#f9ef77,#F8DC2E) no-repeat;background:#F8DC2E -moz-linear-gradient(top,#f9ef77,#F8DC2E) no-repeat;background:#F8DC2E linear-gradient(top,#f9ef77,#F8DC2E) no-repeat;-ms-filter:"progid:DXImageTransform.Microsoft.gradient(startColorstr=#f9ef77, endColorstr=#F8DC2E)" no-repeat}.win_title{font-weight:700;font-size:24px}.win_avp_switch{margin:20px 0}h3{font-size:18px}.entry-section-heading{font-size:16px;font-weight:700;margin:20px auto}</style>
</head>
<body>
<div class="wrapper">
#{win_heading.to_html}
<h3>Credits</h3>
#{tables.each_with_index{|tbl,idx| tbl.to_html}}
</div>
</body>
</html>
EOS
end

Dir.glob("**/*.html").each do |filename|
	html = Nokogiri::HTML(File.read(filename, :encoding => Encoding::UTF_8).gsub(/\r/, ""))
	File.rename(filename, filename.gsub(/\.html/, ".original.html"))
	File.open(filename, "w") do |file|
		file.puts conv_html(html)
	end
end
