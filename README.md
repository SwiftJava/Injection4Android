## Injection4Android, Run-time code injection for Android.

Build and run this app to support run-time code injection in your android application. This means
you'll be able to modify the implementation of non-final methods in your Swift classes and
have the changes take effect without having to load the apk re-run the application.

The application needs to include [https://github.com/SwiftJava/swift-android-injection.git](https://github.com/SwiftJava/swift-android-injection)
in your application's Package.swift and at some time during initialisation make the
following call:

        AndroidInjection.connectAndRun(forMainThread: {
            closurePerformingInjection in
            responder.onMainThread( ClosureRunnable(closurePerformingInjection) )
        })

The Java function onMainThread will run the actual load of the shared library on the main
thread as this is more reliable. On some devices you may be able to not provide the closure
argument and still have reliable injections. See the example applications
[swift-android-samples](https://github.com/SwiftJava/swift-android-samples) and
[swift-android-kotlin](https://github.com/SwiftJava/swift-android-kotlin) for more details.

This will try to connect to the Injection4Android app using the IP address updated by the current
gradle plugin. When your app connects it will set up a file watcher on your project and whenever
you save a swift file it will build your project, package the object file associated with the source
as a shared library and copy it to the device and load it. When loaded AndroidInjection knows
how to find which classes are contained in the shared library and "swizzles" the
new implementations onto the original version of the class by overwritting its vtable.

You can only inject non-final methods of non-final classes and methods on structs. Also
any static variables in the class being injected should be separated into a separate file
if you want them to maintain their state. This is because the new method implemntations
will be linked to refer to static variables in the new version of the class otherwise.
