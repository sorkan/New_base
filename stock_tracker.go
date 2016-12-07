package main

import (
	"strings"
	"fmt"
	"urllib"
	"flag"
	"regexp"
	"os"
	"log"
)

// ----------------------------------------------------------------------------
// This function performs string replacement of literals by using regexp to
// compile the passed in pattern.  Then in the original string make the replacement
// of the pattern with the string/char
func replace_values(pattern string, orig_str string, rep_char string) string {
	repl,_:=regexp.Compile(pattern)
	new_str:=repl.ReplaceAllLiteralString(orig_str, rep_char)

	return new_str
}

func main() {
	var tickerSym string
	var outputFile string
	var data_values [][]string

	header := "Symbol,Previous_Close,Open,Bid,Ask,Days_Range,52_Week_Range,Volume,"
	header = header + "Avg_Volume,Market_Cap,Beta,PE_Ratio,EPS(TTM),Earnings_Date,"
	header = header + "Dividend_and_Yield,Ex_Dividend_Date,1yr_Target_Est"

	ofileName := "StockTracker_Out.csv"
	data_values = append(data_values, strings.Split(header, ","))
	FIN_SITE:="http://finance.yahoo.com/quote/"

	flag.StringVar(&tickerSym,"sym", "CTSH", "a comma separated list of strings")
	flag.StringVar(&outputFile, "csvfile", ofileName, "A file to write out the run details")
	flag.Parse()

	fmt.Println("STOCK SYM: ", tickerSym)

	SYMBOLS := strings.Split(tickerSym, ",")
	for _,sym := range SYMBOLS {
		var sub_row []string
		symUpper := strings.ToUpper(sym)
		TEMP_SITE:=FIN_SITE + symUpper + "?ltr=1"
		fmt.Printf("Processing for symbol: %s\n", symUpper)

		req := urllib.Get(TEMP_SITE)
		req.Debug(true)
		str, err := req.String()
		if err != nil {
			log.Fatalln("Unable to process symbol", err.Error())
			continue
		}

		regstring:=regexp.MustCompile("\\<div id=\"quote-summary\".*\\>(.*)\\</div\\>")
		match_temp := regstring.FindAllString(str, -1)
		if len(match_temp) == 0 {
			fmt.Printf("\tUnable to process symbol: %s\n", symUpper)
			continue
		}

		regstring2 := regexp.MustCompile("\\<tr(.*?)\\>\\<td(.*?)\\>\\<span(.*?)\\>(.*?)\\</span\\>\\</td\\>\\<td(.*?)\\>(.*?)\\</td\\>\\</tr\\>")
		match_list2 := regstring2.FindAllString(match_temp[0], -1)

		sub_row=append(sub_row, symUpper)
		for _,line := range match_list2 {
			rx:=regexp.MustCompile("\\<span data-reactid=.*?\\>(.*?)\\</span\\>.*?\\>\\<td.*?\\>(.*?)\\</td\\>")
			mx:= rx.FindString(line)

			new_str:= replace_values("&#x27;",
				replace_values("&amp;",
				  	replace_values("\\</td\\>",
						replace_values("\\<td class=.*?\\>",
							replace_values("\\</span\\>",
								replace_values("\\<span data-reactid=.*?\\>", mx, ""),
							"|"),
						""),
				  	""),
				"&"),
			"'")

			vals:=strings.Split(new_str, "|")
			sub_row = append(sub_row, vals[1])
			//fmt.Println(new_str, vals)
		}
		data_values = append(data_values, sub_row)
	}

	// create file for writing
	ofile,err := os.Create(outputFile)
	if err != nil {
		log.Fatalln("Unable to create output file", err.Error())
		os.Exit(-1)
	}
	defer ofile.Close()

	for _,lines := range data_values {
		outStr := strings.Join(lines, ",")
		_, err = ofile.WriteString(outStr + "\n")
		if err != nil {
			log.Fatalln("Error writing to file: ", err.Error())
			os.Exit(-1)
		}
	}

	fmt.Printf("\n\nRun results written to: %s\n\n", outputFile)
}

