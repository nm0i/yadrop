namespace eval etitle {}
# Сбрасываем значения всех переменных.
foreach p [array names etitle *] { catch {unset etitle($p) } }

# Seconds before next request.
set etitle(delay) 1

# List of ignored nicks.
set etitle(denynicks) "ChanServ"

# List of ignored words in titles.
set etitle(denywords) "LeechCraft"

# Maximum amount of redirects.
set etitle(redirects) "19"

package require http
package require tls 
package require autoproxy
autoproxy::init

http::register https 443 autoproxy::tls_socket

# Процедура обработки запроса.
proc ::etitle::etitle_proc {nick uhost hand chan text} {
    global etitle  botnick

    foreach dnick [split $etitle(denynicks)] {
        if {$nick == $dnick} {
            return 0
        }
    }

    if {[info exists etitle(lasttime,$chan)] && [expr $etitle(lasttime,$chan) + $etitle(delay)] > [clock seconds]} {
        return 0
    }

    set query [lindex [split $text] [lsearch [split $text] "*://*"]]
    set query [string trim [join $query] \x20\x5B\x5D\x7B\x7D\x28\x29\x22\x27\x09]

    if {[string match "*#*" $query]} {
        regsub -nocase "http://" $query "" query
        if {[string match "*/*#*/*" $query]} {
            set query http://[join [lreplace [split $query "/"] [lsearch [split $query "/"] *#*] [lsearch [split $query "/"] *#*]] "/"]
        } else {
            set query http://[lindex [split $query "#"] 0]
        }
    }

    ::etitle::etitle_parce $nick $uhost $hand $chan $query 0 [clock clicks]
    set etitle(lasttime,$chan) [clock seconds]
}

# Проедура парсинга.
proc ::etitle::etitle_parce {nick uhost hand chan query redirect start} {
	global etitle 
    autoproxy::configure -host 127.0.0.1 -port 8118
    set etitle_tok [::http::config  -urlencoding utf-8 -useragent "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 2.0.50727; .NET CLR 3.0.04506.30)"]
    set etitle_tok [::http::geturl "$query" -binary 1 -timeout 20000 -headers [list Range "bytes=0-16384"]]  
    set data [::http::data $etitle_tok]
    set title "No title"
    upvar #0 $etitle_tok state

    foreach {name value} $state(meta) {
		#    putlog "$name $value"
		if {[regexp -nocase ^location$ $name]} {
			set newurl $value
		} 
    }

    if {$redirect < $etitle(redirects)} {
        if {[info exists newurl] && $newurl != ""} {
            if {[string first "/" $newurl] == "0"} { 
                regexp -- {://(.*?)/} $query -> baseurl
                regexp -- {www.(.*?)/} $query -> baseurl
                if {[info exists baseurl] && $baseurl != ""} {
                    set newurl http://$baseurl$newurl
                    ::etitle::etitle_parce $nick $uhost $hand $chan $newurl [incr redirect] $start
                    return 0
                } else {
                    set newurl $query$newurl
                    ::etitle::etitle_parce $nick $uhost $hand $chan $newurl [incr redirect] $start
                    return 0
                }
            } else {
                if {![string match "*http://*" $newurl] && ![string match "*www*" $newurl]} {
                    set newurl $query$newurl
                    ::etitle::etitle_parce $nick $uhost $hand $chan $newurl [incr redirect] $start
                    return 0
                } else {
                    ::etitle::etitle_parce $nick $uhost $hand $chan $newurl [incr redirect] $start
                    return 0
                }
            }  
        }
    } else {
        set title "No title."
        lappend title "Maximum redirects reached: $etitle(redirects)!"
    }

    upvar #0 $etitle_tok state
    foreach {name value} $state(meta) {
		#putlog "$name $value"
        if {[string match -nocase "*Content-Type*" $name] && [string match "*audio*" $value]} {set title "Audio ($value)."}
        if {[string match -nocase "*Content-Type*" $name] && [string match "*video*" $value]} {set title "Video ($value)."}
        if {[string match -nocase "*Content-Type*" $name] && [string match "*image*" $value]} {set title "Image ($value)."}
        if {[string match -nocase "*Content-Type*" $name] && [string match "*application*" $value]} {set title "Application ($value)."}
        if {[string match -nocase "*Content-Disposition*" $name] && [string match "*filename=*" $value]} {lappend title "[lindex [split $value "="] 1]."}
        if {[string match -nocase "*Content-Length*" $name]} {
			if {[string length $value] >= 20} {
                set size "Size: > [::etitle::etitle_bytify [string range $value 0 19]]."
            } else {
                set size "Size: [::etitle::etitle_bytify $value]."
            }
        }
        if {[string match -nocase "*Content-Range*" $name]} {
            set value [lindex [split $value "/"] 1]
            set size "Size: [::etitle::etitle_bytify $value]."
        }
    } 
    if {[info exists size]} {lappend title $size}

    set charset [string map -nocase {"UTF-" "utf-" "iso-" "iso" "windows-" "cp" "shift_jis" "shiftjis"} $state(charset)]

    ::http::cleanup $etitle_tok

    regsub -all -nocase -- {^</title>.*?<title>} $data " | " data
    regsub -all -nocase -- {<!--.*?-->} $data "" data
    regexp -nocase -- {charset[=\"|='|=](.+?)[\ |\"|']} $data "" charset
    regexp -nocase -- {charset','(.+?)'} $data "" charset

	if {$charset == "Unknown"} {
		set data [encoding convertto utf-8 [encoding convertfrom utf-8 $data]]
	}

	if {[string match -nocase "*windows-1251*" $charset]} {
		set data [encoding convertto utf-8 [encoding convertfrom cp1251 $data]]
	}
    
    if {[string match -nocase "*iso8859-1*" $charset]} {
        set data [encoding convertto utf-8 [encoding convertfrom iso8859-1 $data]]
    }

    if {[string match -nocase "*koi8-r*" $charset]} {
        set data [encoding convertto utf-8 [encoding convertfrom koi8-r $data]]
    }

    set data [encoding convertfrom utf-8 $data]

    regexp -nocase -- {<title.*?>(.*?)</title>} $data "" title

    set title [join $title]

    if {[expr [clock clicks] - $start] > 1000000} {
        set time "[expr ([clock clicks] - $start) / 1000 / 1000.]sec."
    } else {
        set time "[expr ([clock clicks] - $start) / 1000.]ms."
    }

    if {[info exists ::sp_version]} {
        set title [encoding convertfrom cp1251 $title]
    }

	#    putserv "PRIVMSG $chan :\[[::etitle::strip.html $title]\]\[$charset/$time\]\[$redirect\]"
	set message "↑ [::etitle::strip.html $title]"
    putserv "PRIVMSG $chan :$message"
	putChanLog k0sh k0sh localhost $chan $message
    set etitle(lasttime,$chan) [clock seconds]
}

# (c) feed.tcl by Vertigo
proc ::etitle::strip.html {t} {
	regsub -all -nocase -- {<.*?>(.*?)</.*?>} $t {\1} t
	regsub -all -nocase -- {<.*?>} $t {} t
	set t [string map {{&amp;} {&}} $t]
	set t [string map -nocase {{&mdash;} {-} {&raquo;} {»} {&laquo;} {«} {&quot;} {"}  \
		{&lt;} {<} {&gt;} {>} {&nbsp;} { } {&amp;} {&} {&copy;} {©} {&#169;} {©} {&bull;} {•} {&#183;} {-} {&sect;} {§} {&reg;} {®} \
		  &#8214; || \
		&#38;      &     &#91;      (     &#92;      /     &#93;      )      &#123;     (     &#125;     ) \
		&#163;     Ј     &#168;     Ё     &#169;     ©     &#171;     «      &#173;     ­     &#174;     ® \
		&#161;     Ў     &#191;     ї     &#180;     ґ     &#183;     ·      &#185;     №     &#187;     » \
		&#188;     ј     &#189;     Ѕ     &#190;     ѕ     &#192;     А      &#193;     Б     &#194;     В \
		&#195;     Г     &#196;     Д     &#197;     Е     &#198;     Ж      &#199;     З     &#200;     И \
		&#201;     Й     &#202;     К     &#203;     Л     &#204;     М      &#205;     Н     &#206;     О \
		&#207;     П     &#208;     Р     &#209;     С     &#210;     Т      &#211;     У     &#212;     Ф \
		&#213;     Х     &#214;     Ц     &#215;     Ч     &#216;     Ш      &#217;     Щ     &#218;     Ъ \
		&#219;     Ы     &#220;     Ь     &#221;     Э     &#222;     Ю      &#223;     Я     &#224;     а \
		&#225;     б     &#226;     в     &#227;     г     &#228;     д      &#229;     е     &#230;     ж \
		&#231;     з     &#232;     и     &#233;     й     &#234;     к      &#235;     л     &#236;     м \
		&#237;     н     &#238;     о     &#239;     п     &#240;     р      &#241;     с     &#242;     т \
		&#243;     у     &#244;     ф     &#245;     х     &#246;     ц      &#247;     ч     &#248;     ш \
		&#249;     щ     &#250;     ъ     &#251;     ы     &#252;     ь      &#253;     э     &#254;     ю \
		&#176;     °     &#8231;    ·     &#716;     .     &#363;     u      &#299;     i     &#712;     ' \
		&#596;     o     &#618;     i     &apos;     ' } $t]
	set t [string map -nocase {&iexcl;    \xA1  &curren;   \xA4  &cent;     \xA2  &pound;    \xA3   &yen;      \xA5  &brvbar;   \xA6 \
		&sect;     \xA7  &uml;      \xA8  &copy;     \xA9  &ordf;     \xAA   &laquo;    \xAB  &not;      \xAC \
		&shy;      \xAD  &reg;      \xAE  &macr;     \xAF  &deg;      \xB0   &plusmn;   \xB1  &sup2;     \xB2 \
		&sup3;     \xB3  &acute;    \xB4  &micro;    \xB5  &para;     \xB6   &middot;   \xB7  &cedil;    \xB8 \
		&sup1;     \xB9  &ordm;     \xBA  &raquo;    \xBB  &frac14;   \xBC   &frac12;   \xBD  &frac34;   \xBE \
		&iquest;   \xBF  &times;    \xD7  &divide;   \xF7  &Agrave;   \xC0   &Aacute;   \xC1  &Acirc;    \xC2 \
		&Atilde;   \xC3  &Auml;     \xC4  &Aring;    \xC5  &AElig;    \xC6   &Ccedil;   \xC7  &Egrave;   \xC8 \
		&Eacute;   \xC9  &Ecirc;    \xCA  &Euml;     \xCB  &Igrave;   \xCC   &Iacute;   \xCD  &Icirc;    \xCE \
		&Iuml;     \xCF  &ETH;      \xD0  &Ntilde;   \xD1  &Ograve;   \xD2   &Oacute;   \xD3  &Ocirc;    \xD4 \
		&Otilde;   \xD5  &Ouml;     \xD6  &Oslash;   \xD8  &Ugrave;   \xD9   &Uacute;   \xDA  &Ucirc;    \xDB \
		&Uuml;     \xDC  &Yacute;   \xDD  &THORN;    \xDE  &szlig;    \xDF   &agrave;   \xE0  &aacute;   \xE1 \
		&acirc;    \xE2  &atilde;   \xE3  &auml;     \xE4  &aring;    \xE5   &aelig;    \xE6  &ccedil;   \xE7 \
		&egrave;   \xE8  &eacute;   \xE9  &ecirc;    \xEA  &euml;     \xEB   &igrave;   \xEC  &iacute;   \xED \
		&icirc;    \xEE  &iuml;     \xEF  &eth;      \xF0  &ntilde;   \xF1   &ograve;   \xF2  &oacute;   \xF3 \
		&ocirc;    \xF4  &otilde;   \xF5  &ouml;     \xF6  &oslash;   \xF8   &ugrave;   \xF9  &uacute;   \xFA \
		&ucirc;    \xFB  &uuml;     \xFC  &yacute;   \xFD  &thorn;    \xFE   &yuml;     \xFF} $t]
        set t [[namespace current]::regsub-eval {&#([0-9]{1,5});} $t {string trimleft \1 "0"}]
        regsub -all {[\x20\x09]+} $t " " t
        regsub -all -nocase -- {<.*?>} $t {} t
        return $t
    }

    proc ::etitle::regsub-eval {re string cmd} {
        return [subst [regsub -all $re [string map {\[ \\[ \] \\] \$ \\$ \\ \\\\} $string] "\[format %c \[$cmd\]\]"]]
    }

proc ::etitle::etitle_bytify {bytes} {
    for {set pos 0; set bytes [expr double($bytes)]} { $bytes >= 1024.0} {set bytes [expr $bytes/1024.0]} {incr pos}
    set a [lindex {"b" "Kb" "Mb" "Gb" "Tb" "Pb"} $pos]
    format "%.3f%s" $bytes $a
}



