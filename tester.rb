#!/usr/bin/env ruby

require 'Tempfile'
require 'Open3'

def cleanup
	begin
		File.delete($programPath) unless $keep
		$compilerOutput.close
		$compilerOutput.unlink
	rescue
	end
end

trap('SIGINT'){
	cleanup
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

def orange(text); colorize(text, "1;31"); end
def red(text); colorize(text, 31); end
def green(text); colorize(text, 32); end
def yellow(text); colorize(text, 33); end
def blue(text); colorize(text, 34); end
def magenta(text); colorize(text, 35); end
def cyan(text); colorize(text, 36); end
def white(text); colorize(text, 37); end

def ask(string)
	puts string
	print "> "
	return gets.strip
end

# sorting taken from http://www.davekoelle.com/files/alphanum.rb
# modified a few lines to make it work

def grouped_compare(a, b)
	loop {
		a_chunk, a = extract_alpha_or_number_group(a)
		b_chunk, b = extract_alpha_or_number_group(b)

		av = a_chunk.to_i
		bv = b_chunk.to_i

		if av.to_s != a_chunk or bv.to_s != b_chunk
			ret = a_chunk <=> b_chunk
		else
			ret = av <=> bv
		end

		return -1 if a_chunk == ''
		return ret if ret != 0
	}
end

def extract_alpha_or_number_group(item)
	matchdata = /([A-Za-z]+|[\d]+)/.match(item)

	if matchdata.nil?
		["", ""]
	else
		[matchdata[0], item = item[matchdata.offset(0)[1] .. -1]]
	end
end

# end of sorting methods

def printCase(caseNum, result, answer, time, pass, dir)
	dir = nil if $doNotShowDirs
	puts "Case #%02s: #{pass}\t%.06ss\t#{dir}" % [caseNum, time] unless $succint
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

opts.on('--nopath', 'Do not show the input file\'s path') { |name|
	$doNotShowDirs = true
}

opts.on('-k', 'Keep the compiled code') { |name|
	$keep = true
}

opts.on('--succint', 'Only show the final statistics.') { |name|
	$succint = true
}

opts.parse!

if $source.nil?
	$source = ask("Source?")
end

if $testDir.nil?
	$testDir = File.realdirpath(ask("Test directory?"))
end

if $max.nil?
	$max = 1.to_f
end

if $inExt.nil?
	$inExt = '.in'
end

if $outExt.nil?
	$outExt = '.out'
end

if $inExt[0] != '.'
	$inExt = '.' + $inExt
end

if $outExt[0] != '.'
	$outExt = '.' + $outExt
end

$programPath = File.join($testDir, File.basename($source, File.extname($source)))

$compilerOutput = Tempfile.new("compiler")

if File.extname($source) == ".c"
	system "gcc -o #{$programPath} #{$source} &> #{$compilerOutput.path}"
elsif File.extname($source) == ".cpp"
	system "g++ -o #{$programPath} #{$source} &> #{$compilerOutput.path}"
else
	puts "This program only works with C or C++ source code."
	exit 1
end

compilerMessages = $compilerOutput.read

unless compilerMessages.empty?
	unless File.exists?($programPath)
		puts red("Couldn't compile the program.")
	end
	puts yellow("Compiler output:")
	puts compilerMessages
end

unless File.exists?($programPath)
	cleanup
	exit 1
end

testCases = []

Find.find($testDir) do |path|
	if File.extname(path) == $inExt
		testCases << path
	end
end

caseNum = -1
passed = timeout = failed = rte = 0

testCases.sort! { |a,b|
	grouped_compare(a,b)
}

for path in testCases
	caseNum += 1
	if $onlyCase.nil? == false and caseNum != $onlyCase
		next
	end
	result = ""
	stdin, stdout, stderr, wait_thr = Open3.popen3($programPath)
	time = Time.now
	begin
		Timeout::timeout($max) do
			begin
				stdin.write(IO.read(path)+"\n")
			rescue Errno::EPIPE
			end
			result = stdout.read
			time = Time.now - time
		end

		answer = IO.read(path[0..-(($inExt.length)+1)]+$outExt)
		answer = (answer.gsub /\r\n?/, "\n").strip
		result = (result.gsub /\r\n?/, "\n").strip

		status = wait_thr.value

		if answer == result
			printCase(caseNum, result, answer, time, green(" OK "), path)
			passed += 1
		elsif status.exited?
			printCase(caseNum, result, answer, time, red(" WA "), path)
			failed += 1
		else
			printCase(caseNum, result, answer, time, orange("RTE "), path)
			rte += 1
		end
	rescue Timeout::Error
		Process.kill('SIGTERM', wait_thr.pid)
		printCase(caseNum, result, answer, (Time.now-time), yellow("TIME"), path)
		timeout += 1
		wait_thr.value # wait the process
	end
	stdin.close
	stdout.close
	stderr.close
end

caseNum = passed+failed+timeout+rte
if caseNum > 0
	if $points.nil?
		puts "%.5s%% correct. (#{passed} out of #{caseNum})"  % ((passed.to_f/caseNum)*100)
	else
		puts "#{passed*$points} points. (#{passed} out of #{caseNum})"
	end
	puts "#{passed} correct, #{timeout} timeouts, #{failed} incorrect, #{rte} runtime errors."
else
	puts red("Error: ")+"No input files found."
	puts "Check that you inputted the correct testing directory, or try setting the -i and -o flags to the extension of the test cases."
	end

cleanup
