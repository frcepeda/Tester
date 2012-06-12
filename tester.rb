#!/usr/bin/env ruby

require 'Tempfile'
require 'Open3'

def cleanup
	begin; File.delete($programPath) unless $keep; rescue; end
	begin; File.delete($evaluatorPath) unless $keep or not $evaluator; rescue; end
	begin; Process.kill('SIGTERM', $wait_thr.pid); rescue; end
	begin; Process.kill('SIGTERM', $ewait_thr.pid) unless not $evaluator; rescue; end
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

# taken from http://stackoverflow.com/questions/2108727/which-in-ruby-checking-if-program-exists-in-path-from-ruby
def isExecutable(cmd)
	exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
	ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
		exts.each { |ext|
			exe = "#{path}/#{cmd}#{ext}"
			return true if File.executable?(exe)
		}
	end
	return false
end

def checkExists(path)
	unless File.exists?(path) or isExecutable(path)
		$stderr.puts "#{path} does not exist."
		exit 1
	end
end

def printCase(caseNum, result, time, pass, dir)
	dir = nil if $doNotShowDirs
	puts "Case #%02s: #{pass}\t%.06ss\t#{dir}" % [caseNum, time] unless $succint
end

# returns path of compiled source
def compile(path)
	return path if isExecutable(path)

	binaryPath = File.join($testDir, File.basename(path, File.extname(path)))

	compilerOutput = Tempfile.new("compiler")

	if File.extname(path) == ".c"
		system "gcc -o #{binaryPath} #{path} &> #{compilerOutput.path}"
	elsif File.extname(path) == ".cpp"
		system "g++ -o #{binaryPath} #{path} &> #{compilerOutput.path}"
	else
		$stderr.puts "This program only works with C or C++ source code."
		exit 1
	end

	compilerMessages = compilerOutput.read

	unless compilerMessages.empty?
		unless File.exists?(binaryPath)
			$stderr.puts red("Couldn't compile #{path}")
		end
		$stderr.puts yellow("Compiler output for #{path}:")
		$stderr.puts compilerMessages
	end

	compilerOutput.close
	compilerOutput.unlink

	unless File.exists?(binaryPath)
		cleanup
		exit 1
	end

	return binaryPath
end

opts = OptionParser.new

opts.banner = "Usage: #{File.basename(__FILE__)} [options] <file to test>\n"

opts.on('-d directory', 'Testing directory') { |dir|
	$testDir = File.realdirpath(dir).strip
}

opts.on('-e evaluator', 'Use this program to evaluate the code.') { |source|
	$evaluator = source.strip
}

opts.on('-t time', 'Maximum time to finish (in seconds)') { |time|
	$max = time.to_f
}

opts.on('-t evalTime', 'Maximum time for -e to evaluate (in seconds)') { |time|
	$evalMax = time.to_f
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

opts.on('-k', 'Keep the compiled code') {
	$keep = true
}

opts.on('--concat', 'Concatenate and send the input and output of the program to the evaluator') { |source|
	$concat = true
}

opts.on('--succint', 'Only show the final statistics.') {
	$succint = true
}

opts.on('--nopath', 'Do not show the input file\'s path') {
	$doNotShowDirs = true
}

opts.parse!

if ARGV.count == 0
	$source = ask("Source?").strip
elsif ARGV.count == 1
	$source = ARGV[0].strip
else
	puts opts
	exit 1
end

$testDir = File.realdirpath(ask("Test directory?")) if $testDir.nil?

$max = 1.to_f if $max.nil?

$evalMax = 1.to_f if $evalMax.nil?

$inExt = '.in' if $inExt.nil?

$outExt = '.out' if $outExt.nil?

$inExt = '.' + $inExt if $inExt[0] != '.'

$outExt = '.' + $outExt if $outExt[0] != '.'

checkExists($source)
checkExists($testDir)

$programPath = compile($source)

if $evaluator
	checkExists($evaluator)
	$evaluatorPath = compile($evaluator)
end

testCases = []

Find.find($testDir) do |path|
	if File.extname(path) == $inExt
		testCases << path
	end
end

caseNum = -1
passed = timeout = failed = rte = evalerrors = 0

testCases.sort! { |a,b|
	grouped_compare(a,b)
}

for path in testCases
	caseNum += 1
	if $onlyCase.nil? == false and caseNum != $onlyCase
		next
	end
	result = ""
	stdin, stdout, stderr, $wait_thr = Open3.popen3($programPath)
	time = Time.now
	begin
		Timeout::timeout($max) do
			begin
				stdin.write(IO.read(path))
				stdin.flush
			rescue Errno::EPIPE
			end
			result = stdout.read
			time = Time.now - time
		end

		answer = IO.read(path[0..-(($inExt.length)+1)]+$outExt)
		answer = (answer.gsub /\r\n?/, "\n").strip
		result = (result.gsub /\r\n?/, "\n").strip

		status = $wait_thr.value

		evaluatorPassed = false

		if $evaluator
			begin
				etime = Time.now
				estdin, estdout, estderr, $ewait_thr = Open3.popen3($evaluatorPath)
				Timeout::timeout($evalMax) do
					begin
						estdin.write(IO.read(path)) if $concat
						estdin.write(result)
						estdin.flush
					rescue Errno::EPIPE
					end
					eresult = estdout.read
				end

				evalstatus = $ewait_thr.value

				raise "ERROR!" if not evalstatus.exited?

				evaluatorPassed = evalstatus.success?
			rescue
				begin
					Process.kill('SIGTERM', $ewait_thr.pid)
				rescue Errno::ESRCH # couldn't kill
				end
				printCase(caseNum, result, (Time.now-etime), magenta("EVAL"), path)
				evalerrors += 1
				next
			end
			estdin.close
			estdout.close
			estderr.close
		end

		if (answer == result and not $evaluator) or evaluatorPassed
			printCase(caseNum, result, time, green(" OK "), path)
			passed += 1
		elsif status.exited?
			printCase(caseNum, result, time, red(" WA "), path)
			failed += 1
		else
			printCase(caseNum, result, time, orange("RTE "), path)
			rte += 1
		end
	rescue Timeout::Error
		begin
			Process.kill('SIGTERM', $wait_thr.pid)
		rescue Errno::ESRCH # couldn't kill
		end
		printCase(caseNum, result, (Time.now-time), yellow("TIME"), path)
		timeout += 1
		$wait_thr.value # wait the process
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
elsif evalerrors > 0
	$stderr.puts red("Error: ")+"Couldn't evaluate."
else
	$stderr.puts red("Error: ")+"No input files found."
	$stderr.puts "Check that you inputted the correct testing directory, or try setting the -i and -o flags to the extension of the test cases."
end

cleanup
