# iOS 7 EZ-Bake

PromiseKit 2 does not easily support iOS 7, sorry, but that’s just how things are in this brave, new, iOS 8 world. This is a generated repository that makes integrating PromiseKit 2 into an iOS 7 project as easy as possible. Simply:

 1. [Download the zip](https://github.com/mxcl/PMKiOS7/archive/master.zip).
 2. Drag and drop the three `PromiseKit.*` files into your project.
 3. Drag and drop any of the sources from the `Categories` directory that you need.

# More Details

* If your project is mixed Objective C and Swift do not add PromiseKit.h to your bridging header.
* If your project is just Swift you do not need the `.h` or the `.m` files.
* If your project is just Objective-C you do not need the `.swift` file.
* Yes, git submodules is a good way to manage this depedency, but just downloading the files and adding them manually is fine too.

# Alternatively

You can install PromiseKit 1.x with CocoaPods all the way back to iOS 5:

```ruby
pod "PromisKit", "~> 1.5"
```
