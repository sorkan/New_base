#!/usr/bin/python
import urllib2
import re
import sys
import os
import getopt
import time

SYMBOL=''
SYMBOLS=[]
get_mode='Calls'
dayrange=''
prevclose=""
openrate=""

if len(sys.argv) < 4:
   print "ERROR: Insufficient args\n\n"
   sys.exit(2)

try:
   opts, args = getopt.getopt(sys.argv[1:],"s:m:d:o:p:",
                   ["stock=","mode=","dayrange=","open=","prev="])
except getopt.GetoptError:
   print 'OPTIONS_SUMMARY.py -s SYM -m [calls or puts] -d "low,high"'
   sys.exit(2)
for opt, arg in opts:
   if opt in ("-s", "--stock"):
      SYMBOL = arg

   elif opt in ("-d", "--dayrange"):
      dayrange = arg

   elif opt in ("-o", "--open"):
      openrate = arg

   elif opt in ("-p", "--prev"):
      prevclose = arg

   elif opt in ("-m", "--mode"):
      inmode=arg
      if inmode in ("calls", "puts"):
         if inmode == 'calls':
            get_mode='Calls'
         else:
            get_mode='Puts'
      else:
         get_mode = 'Calls'

print 'STOCK SYMBOL: ', SYMBOL
print 'Retrieving options details for: %s' %get_mode

YYYYMMDD=time.strftime("%Y%m%d")
outfile='%s-%s-%s.csv' %(SYMBOL, YYYYMMDD, get_mode)
outfh=open(outfile, 'w')
OPT_HDRITEMS=['Option Exp Date','Strike Price', 
              'Contract Name', 
              'Bid', 'Ask', 'Volume', 'Open Interest']

outfh.write('Option: ,%s\r\n' %SYMBOL)
outfh.write('Prev Close:, %s\r\n' %prevclose)
outfh.write('Open rate:, %s\r\n' %openrate)
outfh.write("Day's Range:, %s\r\n\r\n" %dayrange)
OPT_HDR=",".join(OPT_HDRITEMS)
outfh.write("%s\r\n" %OPT_HDR)
optexp_date=''
SYMBOLS.append(SYMBOL)

for STOCK_TKTSYM in SYMBOLS:
   #print "SYM: %s" %STOCK_TKTSYM
   fin_link="http://finance.yahoo.com/q/op?s=%s+Options" %STOCK_TKTSYM

   try:
      req = urllib2.Request(fin_link)
      req.add_header('User-Agent','Mozilla/5.0(iPad; U; CPU iPhone OS 3_2 like Mac OS X; en-us) AppleWebKit/531.21.10 (KHTML, like Gecko) Version/4.0.4 Mobile/7B314 Safari/531.21.10')
      response = urllib2.urlopen(req)
      link=response.read()
   except:
      print "Error opening URL: %s" %STOCK_TKTSYM

   #print link,len(link)
   link=re.sub("\n", '', link)
   optexp_reg='<div class="SelectBox-Pick"><b class=.*>(.*?)<\/b>.*<\/div>'
   optexp_match=re.findall(optexp_reg, link)
   optexp_date=optexp_match[0]

   calls_idxpor=link[link.index('%s' %get_mode):]
   calls_section=calls_idxpor[:calls_idxpor.index('</div></div>')]
   calls_section=re.sub(r'\s+', ' ', calls_section)

   regstring='<tr data-row="(.*?)"(.*?)>(.*?) <\/tr>'
   match_temp=re.findall(regstring, calls_section )
   CALLS_PUTS_ARAY=[]
   One_row=[]
   print "Number of < %s > retrieved: %s " %(get_mode, len(match_temp))
   for elements in match_temp:
     One_row=[]
     (idx, junk, detail)=elements
     rowparser='<td>(.*?)<\/td>'
     row_data=re.findall(rowparser, detail)
     for row in row_data:
       row_ptrn=''
       if 'data-sq=":value"' in row:
          row_ptrn=' <strong .*><a href=.*>(.*?)<\/a><\/strong> '
       elif 'data-sq=":volume"' in row:
          row_ptrn=' <strong .*>(.*?)<\/strong> '
       else:
          if 'href' in row:
             row_ptrn=' <div class=.*><a href=.*>(.*?)<\/a><\/div>'
          else:
             row_ptrn=' <div class=.*>(.*?)<\/div>'

       row_match=re.findall(row_ptrn, row)
       One_row.append(row_match[0])
       #print row_match
     CALLS_PUTS_ARAY.append(One_row)
   # end outer loop

   #print CALLS_PUTS_ARAY
   for rows in CALLS_PUTS_ARAY:
     out_line=[]
     out_line.append('"%s"' %optexp_date)
     out_line.append('"%s"' %rows[0])
     out_line.append('"%s"' %rows[1])
     out_line.append('"%s"' %rows[3])
     out_line.append('"%s"' %rows[4])
     out_line.append('"%s"' %rows[7])
     out_line.append('"%s"' %rows[8])

     outfh.write(",".join(out_line))
     outfh.write("\r\n")
# end for-loop

outfh.close()
