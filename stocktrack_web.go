package main

import (
	"strings"
	"fmt"
	"urllib"
	"regexp"
	//"encoding/json"
	"net/http"
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

func retrievStocksDetails(symbolString string) []string {
	var loc_values []string
	FIN_SITE:="http://finance.yahoo.com/quote/"
	SYMBOLS := strings.Split(symbolString, ",")

	for _,sym := range SYMBOLS {
		var sub_row []string
		symUpper := strings.ToUpper(sym)
		TEMP_SITE:=FIN_SITE + symUpper + "?ltr=1"

		req := urllib.Get(TEMP_SITE)
		req.Debug(true)
		str, err := req.String()
		if err != nil {
			continue
		}

		regstring:=regexp.MustCompile("\\<div id=\"quote-summary\".*\\>(.*)\\</div\\>")
		match_temp := regstring.FindAllString(str, -1)
		if len(match_temp) == 0 {
			continue
		}

		regstring = regexp.MustCompile("\\<tr(.*?)\\>\\<td(.*?)\\>\\<span(.*?)\\>(.*?)\\</span\\>\\</td\\>\\<td(.*?)\\>(.*?)\\</td\\>\\</tr\\>")
		match_list := regstring.FindAllString(match_temp[0], -1)

		sub_row=append(sub_row, "SYMBOL:" + symUpper)
		for _,line := range match_list {
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
			sub_row = append(sub_row, vals[0] + ":" + vals[1])
			//fmt.Println(new_str, vals)
		}
		loc_values = append(loc_values, strings.Join(sub_row, "|"))
	}
	return loc_values
}

// Create a json-like string to be passed back for sake of initial experiment
func Handler(tickerSym string) string{
	sym_json := "[\n"

	data_values := retrievStocksDetails(tickerSym)
	for _,dataLine := range data_values {
		var dataHash []string
		infoLine := strings.Split(dataLine, "|" )
		str_break := strings.Split(infoLine[0], ":")
		new_str := fmt.Sprintf("\"%s\": \"%s\"", strings.ToLower(str_break[0]),str_break[1])
		sym_json = sym_json +  "\t{" + new_str + ",\n\t\t\"dataset\":{\n"

		for _,line_info := range infoLine[1:] {
			str_break = strings.Split(line_info, ":")
			new_str = fmt.Sprintf("\t\t\t\"%s\": \"%s\"", str_break[0], str_break[1])
			dataHash=append(dataHash, new_str)
		}
		sym_json = sym_json + strings.Join(dataHash, ",\n") + "\n\t\t}\n\t},\n"
	}
	sym_json = sym_json[:len(sym_json)-1] + "\n]"
	return sym_json
}

func serveHomeRequest(w http.ResponseWriter, req *http.Request) {
	fmt.Fprintf(w, "Welcome to Stock lookup site")
	fmt.Fprintf(w, "\n\nUse URL: http://localhost:5050/stockprice?sym=symbol1,symbol2,symbol3,...\n\n")
}

func serveStockRequest(w http.ResponseWriter, req *http.Request) {
	res := req.FormValue("sym")
	fmt.Fprintf(w, Handler(res))
}

func main() {
	http.HandleFunc("/", serveHomeRequest)
	http.HandleFunc("/stockprice", serveStockRequest)
	http.ListenAndServe("localhost:5050", nil)
}