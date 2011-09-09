#!/usr/bin/env ruby

trap('SIGINT'){
	begin
	File.delete(programPath) unless $keep
	rescue
	end
	puts
	exit 1
}

require 'timeout'
require 'optparse'
require 'find'
require 'date'

def colorize(text, color_code)
    if STDOUT.tty?
        return "\e[#{color_code}m#{text}\e[0m"
    else
        return text
    end
end

def red(text); colorize(text, 31); end
def green(text); colorize(text, 32); end
def yellow(text); colorize(text, 33); end
def blue(text); colorize(text, 34); end
def magenta(text); colorize(text, 35); end
def cyan(text); colorize(text, 36); end
def white(text); colorize(text, 37); end

def ask(string)
    print string+" "
    return gets.strip
end

def printCase(caseNum, result, answer, time, pass, dir)
    dir = nil unless $showDirs
    puts "Case #%02s: #{pass}\t%.06ss\t#{dir}" % [caseNum, time]
end

opts = OptionParser.new

opts.on('-s file', 'Source file') { |file|
    $source = file.strip
}

opts.on('-d directory', 'Testing directory') { |dir|
    $testDir = File.realdirpath(dir).strip
}

opts.on('-t time', 'Maximum time to finish') { |time|
    $max = time.to_f
}

opts.on('-c case number', 'Only evaluate this case') { |time|
    $onlyCase = time.to_i
}

opts.on('-i extension', 'Extension of input files') { |extension|
    $inExt = extension.strip
}

opts.on('-o extension', 'Extension of output files') { |extension|
    $outExt = extension.strip
}

opts.on('-p points', 'Points per case') { |points|
    $points = points.to_i
}

opts.on('--path', 'Show the input file\'s path') { |name|
    $showDirs = true
}

opts.on('-k', 'Keep the compiled code') { |name|
    $keep = true
}

opts.parse!

if $source.nil?
    $source = ask("Source?")
end

if $testDir.nil?
    $testDir = File.realdirpath(ask("Test directory?"))
end

if $max.nil?
    $max = ask("Maximum time?").to_f
end

if $inExt.nil?
    $inExt = ask("Input extension?")
end

if $outExt.nil?
    $outExt = ask("Output extension?")
end

if $inExt[0] != '.'
    $inExt = '.' + $inExt
end

if $outExt[0] != '.'
    $outExt = '.' + $outExt
end

programPath = File.join($testDir, File.basename($source, File.extname($source)))

if File.extname($source) == ".c"
	system "gcc -o #{programPath} #{$source}"
elsif File.extname($source) == ".cpp"
	system "g++ -o #{programPath} #{$source}"
else
    puts "This program only works with C or C++ source code."
    exit 1
end

caseNum = -1
pass = timeout = fail = 0

Find.find($testDir) do |path|
    if File.extname(path) == $inExt
        caseNum += 1
        if $onlyCase.nil? == false && caseNum != $onlyCase
            next
        end
        result = ""
        test = IO.popen(programPath, 'r+')
        time = Time.now
        begin
            Timeout::timeout($max) do
                test.write(IO.read(path))
                test.write('\n')
                result = test.read
                time = Time.now - time
            end
            answer = IO.read(path[0..-(($inExt.length)+1)]+$outExt)
            answer = (answer.gsub /\r\n?/, "\n").strip
            result = (result.gsub /\r\n?/, "\n").strip
            if answer == result
                printCase(caseNum, result, answer, time, green(" OK "), path)
                pass += 1
            else
                printCase(caseNum, result, answer, time, red("FAIL"), path)
                fail += 1
            end
        rescue Timeout::Error
            Process.kill('SIGTERM', test.pid)
            printCase(caseNum, result, answer, (Time.now-time), yellow("TIME"), path)
            timeout += 1
            test.close
        end
    end
end

caseNum = pass+fail+timeout
if caseNum > 0
    if $points.nil?
        puts "%.5s%% correct. (#{pass} out of #{caseNum}.) #{timeout} timeouts, #{fail} incorrect." % ((pass.to_f/caseNum)*100)
    else
        puts "#{pass*$points} points. (#{pass} out of #{caseNum}.) #{timeout} timeouts, #{fail} incorrect."
    end
else
    puts red("Error: ")+"No input files found."
end

begin
File.delete(programPath) unless $keep
rescue
end
