require "fileutils"

class String
  def throw_away?
    self =~ /\#import \<PromiseKit\/.+\.h\>/ || self =~ /\#import ".+"/
  end
end

# The include order here is important
HEADERS_PRIME = %w{
  .checkout/Sources/Umbrella.h
  .checkout/Sources/AnyPromise.h
  .checkout/Sources/AnyPromise+Private.h
  .checkout/Sources/NSError+Cancellation.h
  .checkout/Sources/PMKPromise.h
  .checkout/Sources/PromiseKit.h
}

def all_headers
  (HEADERS_PRIME + Dir["/.checkout/Sources/*.h"]).uniq
end

############################################################################## 1
File.open("PromiseKit.swift", 'w') do |out|
  Dir[".checkout/Sources/*.swift"].each do |swift_filename|
    out.puts(File.read(swift_filename))
  end 
  
  out.puts('let PMKErrorDomain = "PMKErrorDomain"')
  
  File.read(".checkout/Sources/Umbrella.h").each_line do |line|
    if line =~ /^#define (.+) (@(".+")|((\d+)l))/
      out.puts("let #{$1} = #{$3 || $5}")
    end
  end
end

############################################################################## 2
File.open("PromiseKit.h", 'w') do |out|
  out.puts("#define PMKEZBake")
  out.puts(%Q{#pragma clang diagnostic push})         # doesn't work
  out.puts(%Q{#pragma clang diagnostic ignored "-w"}) # doesn't work

  all_headers.each do |header|
    File.read(header).each_line do |line|
      unless line.throw_away?
        # Older Xcodes don’t like these
        line = line.gsub(/(__)?nonnull/, "")
        line = line.gsub(/(__)?nullable/, "")

        out.write(line)
      end
    end
  end

  out.puts(%Q{#pragma clang diagnostic pop})
end

############################################################################## 3
File.open("PromiseKit.m", 'w') do |out|
  
  files = HEADERS_PRIME + %w{
    .checkout/Sources/NSMethodSignatureForBlock.m
    .checkout/Sources/PMKCallVariadicBlock.m
  }
  files += Dir[".checkout/Sources/*.m"]
  files.uniq!
  
  out.puts("@import Foundation;")
  
  files.each do |header_filename|
    File.read(header_filename).each_line do |line|
      unless line.throw_away?
        # Older Xcodes don’t like these
        line = line.gsub(/(__)?nonnull/, "")
        line = line.gsub(/(__)?nullable/, "")

        out.write(line)
      end
    end
  end
end

############################################################################## 4
FileUtils.rm_r 'Categories', force: true

Dir.chdir('.checkout') do

  Dir['Categories/**/*.swift'].each do |fn|
    FileUtils.mkpath("../#{File.dirname(fn)}")

    File.open("../#{fn}", 'w') do |out|
      File.read(fn).each_line do |line|
        out.write(line) unless line.strip == 'import PromiseKit' or line.strip == "import OMGHTTPURLRQ"
      end
    end
  end

  (Dir['Categories/**/*.h'] + Dir['Categories/**/*.m']).each do |fn|
    FileUtils.mkpath("../#{File.dirname(fn)}")

    File.open("../#{fn}", 'w') do |out|
      File.read(fn).each_line do |line|
        if line.strip.start_with? "#import <PromiseKit"
          out.puts('#import "PromiseKit.h"')
        else
          out.write(line)
        end
      end
    end
  end

end
