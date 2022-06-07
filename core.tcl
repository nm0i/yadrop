#!/usr/bin/tclsh

set confPath "example.conf"

if {[string length [lindex $argv 0]] > 0 } {
    set confPath [lindex $argv 0]
}

if {![file exists $confPath]} {
    puts "No such config file: ${config}"
    exit 1
}

source $confPath

set pidfd [open $pidfile w]
puts $pidfd [pid]
close $pidfd

proc putserv {line} {
    global sockChan
    puts $sockChan $line
}

proc putLog {line} {
    global logChan
    puts $logChan $line
}

proc openLog {fn} {
    global logChan
    set logChan [open $fn a]
    fconfigure $logChan -buffering line
}

proc putChanLog {nick user host chan msg} {
    global logChans
    puts $logChans($chan) "\[[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S} -gmt true]\] <$nick> $msg"
}

proc openChanLog {chan} {
    global logChans
    set logChans($chan) [open "logs/$chan" a]
    fconfigure $logChans($chan) -buffering line
}

proc dismantlePRIVMSG {line} {
    set nick [lindex [regexp -inline {^:(.+?)[! ]} $line] 1]
    set user [lindex [regexp -inline {!(.+?)@} $line] 1]
    set host [lindex [regexp -inline {@(.+?) } $line] 1]
    set chan [lindex [regexp -inline {PRIVMSG (.+?) :} $line] 1]
    set msg  [lindex [regexp -inline { :(.*)$} $line] 1]

    return [list $nick $user $host $chan $msg]
}

proc mainReader {sockChan} {
    global botnick loggedIn channels forever
    set line [gets $sockChan]
    putLog $line
    
    if [eof $sockChan] {
        close $sockChan
        set forever 1
        putLog "Socket died. I shall, too."
        return 0
    }
    
    set code [string range $line [expr 1 + [set indx [string first " " $line]]] [expr [string first " " $line [incr indx]]- 1 ]]
    
    if {!$loggedIn} {
        if {433 == $code} {
            set botnick "${botnick}_"
            putserv "NICK $botnick"
        }
        if {001 == $code} {
            set loggedIn true
            foreach chan $channels {
                putserv "JOIN $chan"
            }
        }
    } else {
        if { "PRIVMSG" == $code} {
            set params [dismantlePRIVMSG $line]
            putChanLog {*}$params						
            if {[string match "*://*" $line]} {
                catch {::etitle::etitle_proc {*}$params} {putLog "Etitle failed: $retVal"}
            }
        }
        if { [string match "PING*" $line] } {
            putserv "PONG"
            putLog "PONG"
        }
    }
}

proc ircConnect {} {
    global sockChan loggedIn
    global server port botnick password
    
    set sockChan [socket $server $port]
    fconfigure $sockChan -buffering line -blocking 0

    set loggedIn false

    if {[info exists password]} {
        putserv "PASS ${password}"
    }
    putserv "USER $botnick localhost localhost: $botnick"
    putserv "NICK $botnick"

    fileevent $sockChan readable [list mainReader $sockChan]
}

#scripts go here
source etitle.tcl

openLog $logfile
foreach chan $channels {
    openChanLog $chan
}

ircConnect

vwait forever


