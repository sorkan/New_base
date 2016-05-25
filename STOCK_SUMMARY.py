#!/usr/bin/python
import urllib2
import re
import sys
import os
import getopt
import time
import commands

SYMBOLS=[]

if len(sys.argv) < 2:
   print "ERROR: Insufficient args"
   print
   sys.exit(2)

try:
   opts, args = getopt.getopt(sys.argv[1:],"s:",["stocks="])
except getopt.GetoptError:
   print 'stocks_rep.py -s <SYM1,SYM2,...>'
   sys.exit(2)
for opt, arg in opts:
   if opt in ("-s", "--stocks"):
      stockslist = arg
      try:
        SYMBOLS=stockslist.split(',')
      except:
        SYMBOLS.append(stockslist)
print 'STOCKS LIST: ', SYMBOLS

YYYYMMDD=time.strftime("%Y%m%d")
outfile='Symbol-%s-summary.csv' %YYYYMMDD
outfh=open(outfile, 'w')
STOCK_HDRITEMS=['Symbol','Previous Close', 'Open', 'Bid', 'Ask', 
                '1y Target Estimate', 'Beta', 'Earnings Date', 
                "Day's Range", '52 week Range', 'Volume', 
                'Average Volume (3 months)', 'Market Cap', 
                'P/E', 'EPS', 'Dividend & Yield']
STOCKHDR=",".join(STOCK_HDRITEMS)
outfh.write("%s\r\n" %STOCKHDR)
STOCKS_LINE=''

for STOCK_TKTSYM in SYMBOLS:
   print "SYM: %s" %STOCK_TKTSYM
   fin_link="http://finance.yahoo.com/q?uhb=uh3_finance_vert&"
   fin_link+="fr=&type=2buttons&s=%s" %STOCK_TKTSYM

   try:
      req = urllib2.Request(fin_link)
      req.add_header('User-Agent','Mozilla/5.0(iPad; U; CPU iPhone OS 3_2 like Mac OS X; en-us) AppleWebKit/531.21.10 (KHTML, like Gecko) Version/4.0.4 Mobile/7B314 Safari/531.21.10')
      response = urllib2.urlopen(req)
      link=response.read()
   except:
      print "Error opening URL: %s" %STOCK_TKTSYM

   #print link,len(link)

   regstring='<div id="yfi_quote_summary_data" class="rtq_table">(.*?)<\/div>'
   match_temp=re.findall(regstring, link)
  
   #newreg_str='<tr><th .*>(.*?)</th><td .*>(.*?)</td></tr>'
   newreg_str='<tr>(.*?)</tr>'
   match_two=re.findall(newreg_str, match_temp[0])
   temp_aray=[]
   temp_aray.append('"%s"' %STOCK_TKTSYM)
   for matches in match_two:
     # find submatches
     #print matches
     submatch_str=''
     if (('Bid:' in matches) or ('Ask:' in matches)):
        submatch_str='<th .*>(.*?)<\/th><td .*><span .*>(.*?)'
        submatch_str+='<\/span><small>(.*?)<\/small><\/td>'
     elif ("Day\'s Range:" in matches):
        submatch_str='<th .*>(.*?)<\/th><td .*><span><span .*>(.*?)<\/span><\/span>.*'
        submatch_str+='<span><span .*>(.*?)<\/span><\/span><\/td>'
     elif ('52wk Range:' in matches):
        submatch_str='<th .*>(.*?)<\/th><td .*><span>(.*?)<\/span>.*'
        submatch_str+='<span>(.*?)<\/span><\/td>'
     elif (('Volume:' in matches) or ('Market Cap:' in matches)):
        submatch_str='<th .*>(.*?)<\/th><td .*><span .*>(.*?)<\/span><\/td>'
     elif (('Avg Vol ' in matches) or ('P/E ' in matches) or ('EPS ' in matches)): 
        submatch_str='<th .*>(.*?)<span .*>(.*?)<\/span>:<\/th>'
        submatch_str+='<td .*>(.*?)<\/td>'
     else:
        submatch_str='<th .*>(.*?)<\/th><td .*>(.*?)<\/td>'

     submatch_aray=re.findall(submatch_str, matches)

     #print submatch_aray
     try:
       if len(submatch_aray[0]) == 2:
           (junk1,value)=submatch_aray[0]
           temp_aray.append('"%s"' %value)
       else:
          (junk1,value1,value2)=submatch_aray[0]
          if (' x ' in value2):
            temp_aray.append('"%s"' %value1)
          else:
            if (('3m' in value1) or ('ttm' in value1)):
              temp_aray.append('"%s"' %value2)
            else:
              temp_aray.append('"%s - %s"' %(value1, value2))
     except:
       temp_aray.append('"N/A"')
   
   #print match_two
   #print len(match_two)

   endreq_str='<tr class="end"><th .*>(.*?)</th><td .*>(.*?)</td></tr>'
   match_end=re.findall(endreq_str, match_temp[0])
   #print match_end
   (junk1, value)=match_end[0]
   temp_aray.append('"%s"' %value)
   prev_close=temp_aray[1]
   open_rate=temp_aray[2]
   dayrange=temp_aray[8]
   
   outfh.write(",".join(temp_aray))
   outfh.write("\r\n")

   # run external script to get option calls and puts
   cmd="./OPTIONS_SUMMARY.py --stock=%s --dayrange='%s' " %(STOCK_TKTSYM,dayrange)
   cmd+="--open=%s --prev=%s --mode=calls" %(open_rate,prev_close)
   (status,output)=commands.getstatusoutput(cmd)
   print "Output: ",output
   print "Status: ",status

   cmd="./OPTIONS_SUMMARY.py --stock=%s --dayrange='%s' " %(STOCK_TKTSYM,dayrange)
   cmd+="--open=%s --prev=%s --mode=puts" %(open_rate,prev_close)
   (status,output)=commands.getstatusoutput(cmd)
   print "Output: ",output
   print "Status: ",status
# end for-loop

outfh.close()
