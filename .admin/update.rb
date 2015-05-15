class String
  def throw_away?
    self =~ /\#import \<PromiseKit\/.+\.h\>/ || self =~ /\#import ".+"/
  end
end

File.open("PromiseKit.swift", 'w') do |out|
  %w{
    .checkout/Sources/AnyPromise.swift
    .checkout/Sources/ErrorUnhandler.swift
    .checkout/Sources/NSJSONFromData.swift
    .checkout/Sources/Promise+Properties.swift
    .checkout/Sources/Promise.swift
    .checkout/Sources/Sealant.swift
    .checkout/Sources/State.swift
    .checkout/Sources/after.swift
    .checkout/Sources/dispatch_promise.swift
    .checkout/Sources/race.swift
    .checkout/Sources/when.swift
  }.each do |swift_filename|
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
  out.puts(%Q{#pragma clang diagnostic push})
  out.puts(%Q{#pragma clang diagnostic ignored "-w"})

  %w{
    .checkout/Sources/Umbrella.h
    .checkout/Sources/AnyPromise.h
    .checkout/Sources/AnyPromise+Private.h
    .checkout/Sources/NSError+Cancellation.h
    .checkout/Sources/PMKPromise.h
    .checkout/Sources/PromiseKit.h
  }.each do |header|
    File.read(header).each_line do |line|
      out.write(line) unless line.throw_away?
    end
  end

  out.puts(%Q{#pragma clang diagnostic pop})
end

File.open("PromiseKit.m", 'w') do |out|
  
  files = %w{
    .checkout/Sources/Umbrella.h
    .checkout/Sources/AnyPromise.h
    .checkout/Sources/AnyPromise+Private.h
    .checkout/Sources/NSError+Cancellation.h
    .checkout/Sources/PMKPromise.h
    .checkout/Sources/PromiseKit.h
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