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

File.open("PromiseKit.h", 'w') do |out|
  out.puts("#define PMKEZBake")
  out.puts(%Q{#pragma clang diagnostic push})         # doesn't work
  out.puts(%Q{#pragma clang diagnostic ignored "-w"}) # doesn't work

  all_headers.each do |header|
    File.read(header).each_line do |line|
      out.write(line) unless line.throw_away?
    end
  end

  out.puts(%Q{#pragma clang diagnostic pop})
end

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
      out.write(line) unless line.throw_away?
    end
  end
end