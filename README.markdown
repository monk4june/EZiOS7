# iOS 7 EZ-Bake

PromiseKit 2 does not easily support iOS 7, sorry, but that’s just how things are in this brave, new, iOS 8 world. This is a generated repository that makes integrating PromiseKit 2 into an iOS 7 project as easy as possible. Simply:

 1. [Download the zip](https://github.com/mxcl/PMKiOS7/archive/master.zip).
 2. Drag and drop the three `PromiseKit.*` files into your project.
 3. Drag and drop any of the sources from the `Categories` directory that you need.
 
***Please note that you will almost certainly want sources from the `Categories` directory. If you eg. are surprised that you aren’t getting any completion for promises on `NSURLConnection`, `UIAlertView` or `UIView` objects it is because you must add these sources manually from the `Categories` directory!***

# More Details

* If your project is mixed (Objective-C & Swift) do not add `PromiseKit.h` to your bridging header.
* If your project is just Swift you do not need the `.h` or the `.m` files.
* If your project is just Objective-C you ***DO*** still need the `.swift` file.
* `git submodules` seems like a good way to manage this depedency, but just downloading the files and adding them manually works fine.

# *Please* Note 1

If your project is mixed Objective-C and Swift and you need to import your generated Swift header you must import the generated header first:

```objc
#import "YourProject-Swift.h"
#import "PromiseKit.h"
```

# *Please* Note 2

If you want the `NSURLConnection` categories, you will need to install [OMGHTTPURLRQ](https://github.com/mxcl/OMGHTTPURLRQ):

```ruby
pod "OMGHTTPURLRQ"
```

# Alternatively

You can install PromiseKit 1.x with CocoaPods all the way back to iOS 5:

```ruby
pod "PromisKit", "~> 1.5"
```

*Please note*, there is no Swift support with PromiseKit 1.x.
