#!/usr/bin/env ruby

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

def printCase(caseNum, result, answer, time, pass)
    caseN = caseNum.to_s
    width = `tput cols`.to_i
    unless $simple
        if result.split("\n").count > 1 || answer.split("\n").count > 1
            puts "Case ##{caseN}: #{pass}\t#{time}"
            i = -1
            aLines = answer.split("\n")
            for line in result.split("\n")
                i += 1
                puts magenta("\t#{line}\t\t#{aLines[i]}")
            end
        else
            string = "Case ##{caseN}: #{result} => #{answer}"
            puts string+"%#{width - string.length - pass.length + 9 - 1}s #{pass}" % time.to_s # 9 is the number of extra characters to output color
        end
    else
        puts "Case ##{caseN}: #{pass}\t#{time}"
    end
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

opts.on('-c case number', 'Only evaluate this case.') { |time|
    $onlyCase = time.to_i
}

opts.on('-i extension', 'Extension of input files.') { |extension|
    $inExt = extension.strip
}

opts.on('-o extension', 'Extension of output files.') { |extension|
    $outExt = extension.strip
}

opts.on('--simple', 'Only show pass or fail') { |name|
    $simple = true
}

opts.on('-k', 'Keep the compiled code') { |name|
    $keep = true
}

opts.parse!

if $source.nil?
    $source = ask("Source?").strip
end

if $testDir.nil?
    $testDir = File.realdirpath(ask("Test directory?")).strip
end

if $max.nil?
    $max = ask("Maximum time?").to_f
end

if $inExt.nil?
    $inExt = '.in'
end

if $outExt.nil?
    $outExt = '.out'
end

programPath = '"#{File.join($testDir, File.basename($source, File.extname($source))}"'

system "gcc -o #{programPath} #{$source}"
caseNum = -1
pass = 0
timeout = 0
fail = 0
Find.find($testDir) do |path|
    if File.extname(path) == $inExt
        caseNum += 1
        if $onlyCase.nil? == false && caseNum != $onlyCase
            next
        end
        result = ""
        time = Time.now
        IO.popen(programPath, 'r+') {|test|
            start = Time.now
            test.write(IO.read(path))
            result = test.read
            time = Time.now - start
        }
        answer = IO.read(path[0..-4]+$outExt)
        answer = (answer.gsub /\r\n?/, "\n").strip
        result = (result.gsub /\r\n?/, "\n").strip
        if answer == result
            if time < $max
                printCase(caseNum, result, answer, time, green(" OK "))
                pass += 1
            else
                printCase(caseNum, result, answer, time, yellow("TIME"))
                timeout += 1
            end
        else
            printCase(caseNum, result, answer, time, red("FAIL"))
            fail += 1
        end
    end
end

unless $onlyCase.nil?
    caseNum = 1
end

puts "Got #{(pass.to_f/caseNum)*100}% correct. (#{pass} out of #{caseNum}.) #{timeout} timeouts, #{fail} incorrect."

begin
File.delete(programPath) unless $keep
rescue
end