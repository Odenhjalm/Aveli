oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ cd ~/Wisdom/backend
poetry run uvicorn app.main:app --reload
INFO:     Will watch for changes in these directories: ['/home/oden/Wisdom/backend']
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Started reloader process [387995] using WatchFiles
INFO:     Started server process [388000]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
WARNING:  WatchFiles detected changes in 'app/models.py'. Reloading...
INFO:     Shutting down
INFO:     Waiting for application shutdown.
INFO:     Application shutdown complete.
INFO:     Finished server process [388000]
INFO:     Started server process [392895]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Shutting down
INFO:     Waiting for application shutdown.
INFO:     Application shutdown complete.
INFO:     Finished server process [392895]
INFO:     Stopping reloader process [387995]
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$ flutter emulators --launch Pixel_7_API34
flutter run -d emulator-5554
Changing current working directory to: /home/oden/Wisdom
Launching lib/main.dart on sdk gphone64 x86 64 in debug mode...
I/flutter ( 4168): Auth login failed: The connection errored: Connection refused This indicates an error which most likely cannot be solved by the library.
Running Gradle task 'assembleDebug'...                              4.7s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...        1,306ms
D/FlutterJNI( 4852): Beginning load of flutter...
D/FlutterJNI( 4852): flutter (null) was loaded normally!
I/flutter ( 4852): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
E/OpenGLRenderer( 4852): Unable to match the desired swap behavior.
Syncing files to device sdk gphone64 x86 64...                      87ms

Flutter run key commands.
r Hot reload. 🔥🔥🔥
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on sdk gphone64 x86 64 is available at: http://127.0.0.1:41037/R4puJAjujC4=/
The Flutter DevTools debugger and profiler on sdk gphone64 x86 64 is available at:
http://127.0.0.1:9101?uri=http://127.0.0.1:41037/R4puJAjujC4=/
D/EGL_emulation( 4852): app_time_stats: avg=10.73ms min=1.30ms max=71.35ms count=47
D/EGL_emulation( 4852): app_time_stats: avg=3.70ms min=1.42ms max=19.78ms count=56
D/EGL_emulation( 4852): app_time_stats: avg=3.27ms min=1.51ms max=19.12ms count=58
D/EGL_emulation( 4852): app_time_stats: avg=4.20ms min=1.36ms max=22.46ms count=57
W/WindowOnBackDispatcher( 4852): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4852): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
D/ProfileInstaller( 4852): Installing profile for com.example.andlig_app
D/EGL_emulation( 4852): app_time_stats: avg=87.04ms min=0.83ms max=1342.84ms count=20
I/ImeTracker( 4852): com.example.andlig_app:2ea79910: onRequestShow at ORIGIN_CLIENT_SHOW_SOFT_INPUT reason SHOW_SOFT_INPUT
D/InputMethodManager( 4852): showSoftInput() view=io.flutter.embedding.android.FlutterView{87b7138 VFE...... .F....ID 0,0-1080,2337 #2 aid=1073741824} flags=0 reason=SHOW_SOFT_INPUT
I/AssistStructure( 4852): Flattened final assist data: 736 bytes, containing 1 windows, 4 views
D/InsetsController( 4852): show(ime(), fromIme=true)
I/ImeTracker( 4852): com.example.andlig_app:2ea79910: onShown
D/EGL_emulation( 4852): app_time_stats: avg=47.83ms min=2.85ms max=499.78ms count=28
D/EGL_emulation( 4852): app_time_stats: avg=500.63ms min=499.75ms max=501.52ms count=2
D/EGL_emulation( 4852): app_time_stats: avg=499.72ms min=499.23ms max=500.40ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=361.56ms min=85.17ms max=500.51ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=280.39ms min=16.88ms max=499.18ms count=4
D/EGL_emulation( 4852): app_time_stats: avg=409.01ms min=241.20ms max=493.44ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=380.96ms min=226.85ms max=490.19ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=380.08ms min=159.36ms max=490.71ms count=3
E/FrameTracker( 4852): force finish cuj, time out: J<IME_INSETS_ANIMATION::0@1@com.example.andlig_app>
D/EGL_emulation( 4852): app_time_stats: avg=455.43ms min=373.66ms max=499.42ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=316.70ms min=26.40ms max=491.99ms count=4
D/EGL_emulation( 4852): app_time_stats: avg=500.17ms min=499.85ms max=500.49ms count=2
D/EGL_emulation( 4852): app_time_stats: avg=259.81ms min=15.34ms max=499.84ms count=4
D/EGL_emulation( 4852): app_time_stats: avg=366.63ms min=108.32ms max=499.68ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=380.13ms min=289.58ms max=493.28ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=447.87ms min=357.11ms max=494.01ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=388.78ms min=154.15ms max=512.25ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=411.07ms min=241.47ms max=498.92ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=499.83ms min=498.40ms max=500.86ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=352.33ms min=57.60ms max=507.57ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=372.08ms min=123.43ms max=499.88ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=419.83ms min=272.85ms max=493.50ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=483.63ms min=460.12ms max=500.65ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=341.20ms min=255.10ms max=493.90ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=368.64ms min=113.70ms max=500.24ms count=3
I/ImeTracker( 4852): com.example.andlig_app:dfdd578: onRequestShow at ORIGIN_CLIENT_SHOW_SOFT_INPUT reason SHOW_SOFT_INPUT
D/InputMethodManager( 4852): showSoftInput() view=io.flutter.embedding.android.FlutterView{87b7138 VFE...... .F...... 0,0-1080,2337 #2 aid=1073741824} flags=0 reason=SHOW_SOFT_INPUT
D/InsetsController( 4852): show(ime(), fromIme=true)
I/ImeTracker( 4852): com.example.andlig_app:dfdd578: onCancelled at PHASE_CLIENT_APPLY_ANIMATION
D/EGL_emulation( 4852): app_time_stats: avg=83.58ms min=14.19ms max=499.85ms count=12
D/EGL_emulation( 4852): app_time_stats: avg=250.07ms min=1.22ms max=496.95ms count=5
D/EGL_emulation( 4852): app_time_stats: avg=335.56ms min=189.38ms max=493.76ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=459.12ms min=390.28ms max=493.91ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=488.79ms min=472.12ms max=499.79ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=372.17ms min=124.41ms max=499.49ms count=3
W/WindowOnBackDispatcher( 4852): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4852): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
I/flutter ( 4852): Auth login failed: The connection errored: Connection refused This indicates an error which most likely cannot be solved by the library.
W/WindowOnBackDispatcher( 4852): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4852): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
D/EGL_emulation( 4852): app_time_stats: avg=26.15ms min=11.12ms max=184.42ms count=38
D/EGL_emulation( 4852): app_time_stats: avg=498.83ms min=496.09ms max=500.42ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=499.85ms min=499.26ms max=500.45ms count=3
D/EGL_emulation( 4852): app_time_stats: avg=74.99ms min=13.91ms max=500.89ms count=20
D/EGL_emulation( 4852): app_time_stats: avg=500.10ms min=499.90ms max=500.30ms count=2
D/EGL_emulation( 4852): app_time_stats: avg=499.85ms min=499.29ms max=500.46ms count=3
Lost connection to device.
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$

-x-x--x-x-x-x-x--x-x-x-x-x--x-x-x-x-x-x-x--x-x-x-x-x-z-x-x-xx--x-----xx-x--x-x-

oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ emulator -avd Pixel_7_API34 -wipe-data -no-snapshot
INFO         | Android emulator version 36.1.9.0 (build_id 13823996) (CL:N/A)
INFO         | Graphics backend: gfxstream
INFO         | Found systemPath /home/oden/Android/Sdk/system-images/android-34/google_apis/x86_64/
INFO         | Increasing RAM size to 2048MB
INFO         | Guest GLES Driver: Auto (ext controls)
library_mode host gpu mode host
INFO         | emuglConfig_get_vulkan_hardware_gpu_support_info: Found physical GPU 'Intel(R) Graphics (ARL)', type: VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU, apiVersion: 1.4.305, driverVersion: 25.0.7

INFO         | emuglConfig_get_vulkan_hardware_gpu_support_info: Found physical GPU 'llvmpipe (LLVM 20.1.2, 256 bits)', type: VK_PHYSICAL_DEVICE_TYPE_CPU, apiVersion: 1.4.305, driverVersion: 0.0.1

INFO         | Enabled VulkanAllocateHostMemory feature for gpu vendor Intel(R) Graphics (ARL) on Linux

INFO         | GPU device local memory = 7697MB
INFO         | Checking system compatibility:
INFO         |   Checking: hasSufficientDiskSpace
INFO         |      Ok: Disk space requirements to run avd: `Pixel_7_API34` are met
INFO         |   Checking: hasSufficientHwGpu
INFO         |      Ok: Hardware GPU requirements to run avd: `Pixel_7_API34` are passed
INFO         |   Checking: hasSufficientSystem
INFO         |      Ok: System requirements to run avd: `Pixel_7_API34` are met
INFO         | Warning: Could not find the Qt platform plugin "wayland" in "/home/oden/Android/Sdk/emulator/lib64/qt/plugins" (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_btn_xr_environment_living_room_day_clicked() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_btn_xr_environment_living_room_night_clicked() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_new_posture_requested(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_posture_selection_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_new_resizable_requested(PresetEmulatorSizeType) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_resizable_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_xr_environment_mode_changed(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_xr_environment_mode_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_xr_input_mode_changed(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_xr_input_mode_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_sleep_timer_done() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_unfold_timer_done() (:0, )
INFO         | Storing crashdata in: /tmp/android-oden/emu-crash-36.1.9.db, detection is enabled for process: 358933
INFO         | Initializing hardware OpenGLES emulation support
I1007 02:03:50.001575  358933 opengles.cpp:291] android_startOpenglesRenderer: gpu info
I1007 02:03:50.001601  358933 opengles.cpp:292]
INFO         | HealthMonitor disabled.
INFO         | SharedLibrary::open for [libvulkan.so]
INFO         | SharedLibrary::open for [libvulkan.so]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libvulkan.so] (posix): begin
INFO         | SharedLibrary::open for [libvulkan.so] (posix,linux): call dlopen on [libvulkan.so]
INFO         | SharedLibrary::open succeeded for [libvulkan.so].
INFO         | Added library: libvulkan.so
INFO         | Selecting Vulkan device: Intel(R) Graphics (ARL), Version: 1.4.305
INFO         | Disabling sparse binding feature support
INFO         | SharedLibrary::open for [libX11]
INFO         | SharedLibrary::open for [libX11]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libX11] (posix): begin
INFO         | SharedLibrary::open for [libX11] (posix,linux): call dlopen on [libX11.so]
INFO         | SharedLibrary::open succeeded for [libX11].
INFO         | SharedLibrary::open for [libGL.so.1]
INFO         | SharedLibrary::open for [libGL.so.1]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libGL.so.1] (posix): begin
INFO         | SharedLibrary::open for [libGL.so.1] (posix,linux): call dlopen on [libGL.so.1]
INFO         | SharedLibrary::open succeeded for [libGL.so.1].
INFO         | SharedLibrary::open for [libshadertranslator.so]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libshadertranslator.so] (posix): begin
INFO         | SharedLibrary::open for [libshadertranslator.so] (posix,linux): call dlopen on [libshadertranslator.so]
INFO         | SharedLibrary::open succeeded for [libshadertranslator.so].
INFO         | Initializing VkEmulation features:
INFO         |     glInteropSupported: false
INFO         |     useDeferredCommands: true
INFO         |     createResourceWithRequirements: true
INFO         |     useVulkanComposition: false
INFO         |     useVulkanNativeSwapchain: false
INFO         |     enable guestRenderDoc: false
INFO         |     ASTC LDR emulation mode: Gpu
INFO         |     enable ETC2 emulation: true
INFO         |     enable Ycbcr emulation: false
INFO         |     guestVulkanOnly: false
INFO         |     useDedicatedAllocations: false
INFO         | Graphics Adapter Vendor Google (Intel)
INFO         | Graphics Adapter Android Emulator OpenGL ES Translator (Mesa Intel(R) Graphics (ARL))
INFO         | Graphics API Version OpenGL ES 3.0 (4.6 (Core Profile) Mesa 25.0.7-0ubuntu0.24.04.2)
INFO         | Graphics API Extensions GL_OES_EGL_sync GL_OES_EGL_image GL_OES_EGL_image_external GL_OES_depth24 GL_OES_depth32 GL_OES_element_index_uint GL_OES_texture_float GL_OES_texture_float_linear GL_OES_compressed_paletted_texture GL_OES_compressed_ETC1_RGB8_texture GL_OES_depth_texture GL_OES_texture_half_float GL_OES_texture_half_float_linear GL_OES_packed_depth_stencil GL_OES_vertex_half_float GL_OES_texture_npot GL_OES_rgb8_rgba8 GL_EXT_color_buffer_float GL_EXT_color_buffer_half_float GL_EXT_texture_format_BGRA8888 GL_APPLE_texture_format_BGRA8888
INFO         | Graphics Device Extensions N/A
INFO         | Sending adb public key [QAAAAL/NZbvB3d4WH2VeLgo1ktwstBTBV9+lM2i6pSkQoyp2venwXbWJrPaZ8ev594f+7NioRoB+b+9OHCtkU6/fKHxUExFyIAfHJ5Hq1pNK6umaV3p6wKUHDwKxDrxypy/d7c+6utPNWFSOpPxnwLq8SLkfWaDFk6znlHsM+XfA1n39M4wBdyZA1JWuGZNy/U5j0OCB9nihLweahlFSbYbEw7XPDsk9p7NZbI1OsdLJJSxfDZoVwJAqOGGj1l6AjyZT9mssbLJvM4osKmlnA7WiyE4KfccVzZ7v2gCKZQcYH2WJgby0sCuGCYD/vHq221FCGsptQrn67S0FhZEVOVgZ/jI4N8Ohaia9t3eJq0pS1pCRRlRmUg+9WoirHKllfpm/xj6DM2DedaHRqyatGtyjxIoXTqUJtmtD3Y5lQPaS1Oss0xcjLZ9Uqby/C0X5CLONn10bG4F/SDxbWbww8zlBVMk042nPc/0/e/mukF8vDm90AsVOqTOLY8do18+yO8AhVB9K2ve2O7l8sqTg5rkXoos5MHd026S/hHjkbkx9Ed6zp8LHyN+6t56px2O9KmhjikWgVxygPGPY/Zob2qkHlqogtMbv0LWN8ifu9kLi8mXXC1t4DTFFWnSzwIhqg4/uoHEUnGLAlbNtzmjvdvL0TGOqq/MKwJ7iB+BPfBW/dK7BKg6sbgEAAQA= oden@unknown]
I1007 02:03:50.078366  358933 userspace-boot-properties.cpp:766] Userspace boot properties:
I1007 02:03:50.078376  358933 userspace-boot-properties.cpp:770]   androidboot.boot_devices=pci0000:00/0000:00:03.0 pci0000:00/0000:00:06.0
I1007 02:03:50.078378  358933 userspace-boot-properties.cpp:770]   androidboot.dalvik.vm.heapsize=512m
I1007 02:03:50.078379  358933 userspace-boot-properties.cpp:770]   androidboot.debug.hwui.renderer=skiagl
I1007 02:03:50.078380  358933 userspace-boot-properties.cpp:770]   androidboot.hardware=ranchu
I1007 02:03:50.078381  358933 userspace-boot-properties.cpp:770]   androidboot.hardware.gltransport=pipe
I1007 02:03:50.078381  358933 userspace-boot-properties.cpp:770]   androidboot.hardware.vulkan=ranchu
I1007 02:03:50.078382  358933 userspace-boot-properties.cpp:770]   androidboot.logcat=*:V
I1007 02:03:50.078383  358933 userspace-boot-properties.cpp:770]   androidboot.opengles.version=196609
I1007 02:03:50.078386  358933 userspace-boot-properties.cpp:770]   androidboot.qemu=1
I1007 02:03:50.078388  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.adb.pubkey=QAAAAL/NZbvB3d4WH2VeLgo1ktwstBTBV9+lM2i6pSkQoyp2venwXbWJrPaZ8ev594f+7NioRoB+b+9OHCtkU6/fKHxUExFyIAfHJ5Hq1pNK6umaV3p6wKUHDwKxDrxypy/d7c+6utPNWFSOpPxnwLq8SLkfWaDFk6znlHsM+XfA1n39M4wBdyZA1JWuGZNy/U5j0OCB9nihLweahlFSbYbEw7XPDsk9p7NZbI1OsdLJJSxfDZoVwJAqOGGj1l6AjyZT9mssbLJvM4osKmlnA7WiyE4KfccVzZ7v2gCKZQcYH2WJgby0sCuGCYD/vHq221FCGsptQrn67S0FhZEVOVgZ/jI4N8Ohaia9t3eJq0pS1pCRRlRmUg+9WoirHKllfpm/xj6DM2DedaHRqyatGtyjxIoXTqUJtmtD3Y5lQPaS1Oss0xcjLZ9Uqby/C0X5CLONn10bG4F/SDxbWbww8zlBVMk042nPc/0/e/mukF8vDm90AsVOqTOLY8do18+yO8AhVB9K2ve2O7l8sqTg5rkXoos5MHd026S/hHjkbkx9Ed6zp8LHyN+6t56px2O9KmhjikWgVxygPGPY/Zob2qkHlqogtMbv0LWN8ifu9kLi8mXXC1t4DTFFWnSzwIhqg4/uoHEUnGLAlbNtzmjvdvL0TGOqq/MKwJ7iB+BPfBW/dK7BKg6sbgEAAQA= oden@unknown
I1007 02:03:50.078393  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.avd_name=Pixel_7_API34
I1007 02:03:50.078394  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.camera_hq_edge_processing=0
I1007 02:03:50.078395  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.camera_protocol_ver=1
I1007 02:03:50.078396  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.cpuvulkan.version=4202496
I1007 02:03:50.078397  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.gltransport.drawFlushInterval=800
I1007 02:03:50.078399  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.gltransport.name=pipe
I1007 02:03:50.078401  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.avcdec=2
I1007 02:03:50.078403  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.hevcdec=2
I1007 02:03:50.078404  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.vpxdec=2
I1007 02:03:50.078405  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.settings.system.screen_off_timeout=2147483647
I1007 02:03:50.078407  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.virtiowifi=1
I1007 02:03:50.078407  358933 userspace-boot-properties.cpp:770]   androidboot.qemu.vsync=60
I1007 02:03:50.078409  358933 userspace-boot-properties.cpp:770]   androidboot.serialno=EMULATOR36X1X9X0
I1007 02:03:50.078410  358933 userspace-boot-properties.cpp:770]   androidboot.vbmeta.digest=451e57ed688ff746d2c636d52169ade253e2bc5bb30a5c3ff23679ca15d3bcd3
I1007 02:03:50.078411  358933 userspace-boot-properties.cpp:770]   androidboot.vbmeta.hash_alg=sha256
I1007 02:03:50.078413  358933 userspace-boot-properties.cpp:770]   androidboot.vbmeta.size=6656
I1007 02:03:50.078414  358933 userspace-boot-properties.cpp:770]   androidboot.veritymode=enforcing
INFO         | Monitoring duration of emulator setup.
WARNING      | The emulator now requires a signed jwt token for gRPC access! Use the -grpc flag if you really want an open unprotected grpc port
INFO         | Using security allow list from: /home/oden/Android/Sdk/emulator/lib/emulator_access.json
WARNING      | *** Basic token auth should only be used by android-studio ***
INFO         | The active JSON Web Key Sets can be found here: /run/user/1000/avd/running/358933/jwks/f58771df-9eeb-4a91-b9ce-9d1753f0bff4/active.jwk
INFO         | Scanning /run/user/1000/avd/running/358933/jwks/f58771df-9eeb-4a91-b9ce-9d1753f0bff4 for jwk keys.
INFO         | Started GRPC server at 127.0.0.1:8554, security: Local, auth: +token
INFO         | Advertising in: /run/user/1000/avd/running/pid_358933.ini
INFO         | Setting display: 0 configuration to: 1080x2400, dpi: 420x420
INFO         | setDisplayActiveConfig 0
INFO         | Checking system compatibility:
INFO         |   Checking: hasSufficientDiskSpace
INFO         |      Ok: Disk space requirements to run avd: `Pixel_7_API34` are met
INFO         |   Checking: hasSufficientHwGpu
INFO         |      Ok: Hardware GPU requirements to run avd: `Pixel_7_API34` are passed
INFO         |   Checking: hasSufficientSystem
INFO         |      Ok: System requirements to run avd: `Pixel_7_API34` are met
INFO         | OpenGL Vendor=[Google (Intel)]
INFO         | OpenGL Renderer=[Android Emulator OpenGL ES Translator (Mesa Intel(R) Graphics (ARL))]
INFO         | OpenGL Version=[OpenGL ES 3.0 (4.6 (Core Profile) Mesa 25.0.7-0ubuntu0.24.04.2)]
USER_INFO    | Emulator is performing a full startup. This may take upto two minutes, or more.
WARNING      | adb command '/home/oden/Android/Sdk/platform-tools/adb -s emulator-5554 shell am start-foreground-service -e meter on com.android.emulator.radio.config/.MeterService ' failed: 'adb: device offline'
INFO         | Activated packet streamer for bluetooth emulation
INFO         | Boot completed in 21526 ms
INFO         | Increasing screen off timeout, logcat buffer size to 2M.
INFO         | Wait for emulator (pid 358933) 20 seconds to shutdown gracefully before kill;you can set environment variable ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL(in seconds) to change the default value (20 seconds)

WARNING      | Not saving state: RAM not mapped as shared
INFO         | Saving snapshot 'default_boot' using 8 ms
ERROR        | stop: Not implemented
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ ^C
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ (.venv) oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$ ^C                                         emulator -avd Pixel_7_API34 -wipe-data -no-snapshot
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter emulators --launch Pixel_7_API34
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter run -d emulator-5554
Launching lib/main.dart on sdk gphone64 x86 64 in debug mode...
Running Gradle task 'assembleDebug'...                             13.9s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...        1,396ms
D/FlutterJNI( 4168): Beginning load of flutter...
D/FlutterJNI( 4168): flutter (null) was loaded normally!
I/flutter ( 4168): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
Syncing files to device sdk gphone64 x86 64...                      91ms

Flutter run key commands.
r Hot reload. 🔥🔥🔥
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on sdk gphone64 x86 64 is available at: http://127.0.0.1:42153/KYuhaEDUhSI=/
D/TrafficStats( 4168): tagSocket(118) with statsTag=0xffffffff, statsUid=-1
D/TrafficStats( 4168): tagSocket(121) with statsTag=0xffffffff, statsUid=-1
The Flutter DevTools debugger and profiler on sdk gphone64 x86 64 is available at:
http://127.0.0.1:9101?uri=http://127.0.0.1:42153/KYuhaEDUhSI=/
I/Choreographer( 4168): Skipped 45 frames!  The application may be doing too much work on its main thread.
D/EGL_emulation( 4168): app_time_stats: avg=51.64ms min=2.22ms max=188.41ms count=19
D/EGL_emulation( 4168): app_time_stats: avg=11.31ms min=1.52ms max=51.10ms count=43
D/EGL_emulation( 4168): app_time_stats: avg=12.81ms min=1.54ms max=37.13ms count=46
D/EGL_emulation( 4168): app_time_stats: avg=8.97ms min=1.28ms max=32.35ms count=47
D/ProfileInstaller( 4168): Installing profile for com.example.andlig_app

══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 58 pixels on the right.

The relevant error-causing widget was:
  Row Row:file:///home/oden/Wisdom/lib/features/landing/presentation/landing_page.dart:623:38

To inspect this widget in Flutter DevTools, visit:
http://127.0.0.1:9101/#/inspector?uri=http%3A%2F%2F127.0.0.1%3A42153%2FKYuhaEDUhSI%3D%2F&inspectorRef=
inspector-0

The overflowing RenderFlex has an orientation of Axis.horizontal.
The edge of the RenderFlex that is overflowing has been marked in the rendering with a yellow and
black striped pattern. This is usually caused by the contents being too big for the RenderFlex.
Consider applying a flex factor (e.g. using an Expanded widget) to force the children of the
RenderFlex to fit within the available space instead of being sized to their natural size.
This is considered an error condition because it indicates that there is content that cannot be
seen. If the content is legitimately bigger than the available space, consider clipping it with a
ClipRect widget before putting it in the flex, or using a scrollable container rather than a Flex,
like a ListView.
The specific RenderFlex in question is: RenderFlex#0059f relayoutBoundary=up15 OVERFLOWING:
  creator: Row ← Padding ← Semantics ← DefaultTextStyle ← AnimatedDefaultTextStyle ←
    _InkFeatures-[GlobalKey#7d33a ink renderer] ← NotificationListener<LayoutChangedNotification> ←
    CustomPaint ← _ShapeBorderPaint ← PhysicalShape ← _MaterialInterior ← Material ← ⋯
  parentData: offset=Offset(18.0, 18.0) (can use size)
  constraints: BoxConstraints(0.0<=w<=311.4, 0.0<=h<=Infinity)
  size: Size(311.4, 936.0)
  direction: horizontal
  mainAxisAlignment: start
  mainAxisSize: max
  crossAxisAlignment: center
  textDirection: ltr
  verticalDirection: down
  spacing: 0.0
◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
════════════════════════════════════════════════════════════════════════════════════════════════════

D/EGL_emulation( 4168): app_time_stats: avg=9.90ms min=1.28ms max=170.56ms count=53
D/EGL_emulation( 4168): app_time_stats: avg=6.11ms min=1.28ms max=39.66ms count=54
D/EGL_emulation( 4168): app_time_stats: avg=9.95ms min=1.44ms max=71.20ms count=45
D/EGL_emulation( 4168): app_time_stats: avg=3.07ms min=1.36ms max=20.29ms count=57
D/EGL_emulation( 4168): app_time_stats: avg=2.79ms min=1.15ms max=19.37ms count=57
D/EGL_emulation( 4168): app_time_stats: avg=4.27ms min=1.17ms max=20.07ms count=56
D/EGL_emulation( 4168): app_time_stats: avg=4.22ms min=1.42ms max=20.97ms count=55
D/EGL_emulation( 4168): app_time_stats: avg=4.57ms min=1.29ms max=30.95ms count=56
W/WindowOnBackDispatcher( 4168): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4168): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
I/ImeTracker( 4168): com.example.andlig_app:7529b461: onRequestShow at ORIGIN_CLIENT_SHOW_SOFT_INPUT reason SHOW_SOFT_INPUT
D/EGL_emulation( 4168): app_time_stats: avg=121.01ms min=0.89ms max=1491.54ms count=15
D/InputMethodManager( 4168): showSoftInput() view=io.flutter.embedding.android.FlutterView{7d0cae0 VFE...... .F....ID 0,0-1080,2337 #2 aid=1073741824} flags=0 reason=SHOW_SOFT_INPUT
I/AssistStructure( 4168): Flattened final assist data: 736 bytes, containing 1 windows, 4 views
D/InsetsController( 4168): show(ime(), fromIme=true)
I/ImeTracker( 4168): com.example.andlig_app:7529b461: onShown
D/EGL_emulation( 4168): app_time_stats: avg=43.73ms min=3.80ms max=342.01ms count=21
D/EGL_emulation( 4168): app_time_stats: avg=355.17ms min=4.17ms max=499.79ms count=4
D/EGL_emulation( 4168): app_time_stats: avg=500.06ms min=499.69ms max=500.42ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=499.91ms min=499.58ms max=500.41ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=254.22ms min=24.03ms max=499.56ms count=4
D/EGL_emulation( 4168): app_time_stats: avg=422.22ms min=275.47ms max=499.93ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=372.17ms min=122.97ms max=498.43ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=424.80ms min=391.07ms max=491.92ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=436.37ms min=323.67ms max=492.96ms count=3
E/FrameTracker( 4168): force finish cuj, time out: J<IME_INSETS_ANIMATION::0@1@com.example.andlig_app>
D/EGL_emulation( 4168): app_time_stats: avg=366.33ms min=106.74ms max=499.35ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=417.08ms min=256.38ms max=502.30ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=366.62ms min=106.72ms max=499.57ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=500.47ms min=499.62ms max=502.15ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=499.30ms min=498.05ms max=500.03ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=370.71ms min=10.30ms max=500.56ms count=4
D/EGL_emulation( 4168): app_time_stats: avg=500.06ms min=499.68ms max=500.47ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=364.36ms min=221.66ms max=496.59ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=354.32ms min=73.41ms max=499.79ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=498.11ms min=493.37ms max=502.50ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=256.31ms min=110.79ms max=506.08ms count=4
D/EGL_emulation( 4168): app_time_stats: avg=391.30ms min=162.59ms max=514.96ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=500.16ms min=490.83ms max=508.83ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=407.59ms min=254.34ms max=494.73ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=497.79ms min=493.28ms max=500.22ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=500.40ms min=499.98ms max=500.83ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=368.90ms min=106.34ms max=507.84ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=475.27ms min=438.19ms max=494.70ms count=3
I/ImeTracker( 4168): com.example.andlig_app:7ca8c35a: onRequestShow at ORIGIN_CLIENT_SHOW_SOFT_INPUT reason SHOW_SOFT_INPUT
D/InputMethodManager( 4168): showSoftInput() view=io.flutter.embedding.android.FlutterView{7d0cae0 VFE...... .F...... 0,0-1080,2337 #2 aid=1073741824} flags=0 reason=SHOW_SOFT_INPUT
D/EGL_emulation( 4168): app_time_stats: avg=442.22ms min=327.52ms max=499.64ms count=3
D/InsetsController( 4168): show(ime(), fromIme=true)
I/ImeTracker( 4168): com.example.andlig_app:7ca8c35a: onCancelled at PHASE_CLIENT_APPLY_ANIMATION
D/EGL_emulation( 4168): app_time_stats: avg=98.83ms min=1.16ms max=500.17ms count=14
D/EGL_emulation( 4168): app_time_stats: avg=500.16ms min=500.02ms max=500.30ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=171.55ms min=0.77ms max=495.13ms count=6
D/EGL_emulation( 4168): app_time_stats: avg=475.26ms min=439.87ms max=493.45ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=483.39ms min=456.06ms max=498.66ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=349.87ms min=59.88ms max=500.01ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=379.68ms min=204.67ms max=495.70ms count=3
W/WindowOnBackDispatcher( 4168): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4168): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
I/flutter ( 4168): Auth login failed: The connection errored: Connection refused This indicates an error which most likely cannot be solved by the library.
W/WindowOnBackDispatcher( 4168): OnBackInvokedCallback is not enabled for the application.
W/WindowOnBackDispatcher( 4168): Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.
D/EGL_emulation( 4168): app_time_stats: avg=31.18ms min=12.25ms max=432.10ms count=34
D/EGL_emulation( 4168): app_time_stats: avg=500.14ms min=499.72ms max=500.57ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=499.95ms min=499.06ms max=500.44ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=101.55ms min=15.73ms max=500.39ms count=10
D/EGL_emulation( 4168): app_time_stats: avg=134.97ms min=14.56ms max=501.45ms count=11
D/EGL_emulation( 4168): app_time_stats: avg=499.41ms min=498.34ms max=500.21ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=499.99ms min=499.92ms max=500.02ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=500.00ms min=499.88ms max=500.12ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=500.63ms min=499.75ms max=501.50ms count=2
D/EGL_emulation( 4168): app_time_stats: avg=499.51ms min=498.62ms max=499.99ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=499.96ms min=499.64ms max=500.18ms count=3
D/EGL_emulation( 4168): app_time_stats: avg=500.00ms min=499.77ms max=500.22ms count=2

Application finished.
The Dart compiler exited unexpectedly.
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$


-x-x-x--x-x-x-x-x-x-x-x--x-x-x-x-x--x-x-x-x-x--x--x-x-x-x-x--x-x-x-x-x-x-x-x-x-x-x-




























(oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter clean
Deleting build...                                                    9ms
Deleting .dart_tool...                                               1ms
Deleting ephemeral...                                                0ms
Deleting Generated.xcconfig...                                       0ms
Deleting flutter_export_environment.sh...                            0ms
Deleting ephemeral...                                                0ms
Deleting ephemeral...                                                0ms
Deleting ephemeral...                                                2ms
Deleting .flutter-plugins-dependencies...                            0ms
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter pub get
Resolving dependencies...
Downloading packages...
  _flutterfire_internals 1.3.59 (1.3.62 available)
  characters 1.4.0 (1.4.1 available)
  file_picker 8.3.7 (10.3.3 available)
  firebase_analytics 11.6.0 (12.0.2 available)
  firebase_analytics_platform_interface 4.4.3 (5.0.2 available)
  firebase_analytics_web 0.5.10+16 (0.6.0+2 available)
  firebase_core 3.15.2 (4.1.1 available)
  firebase_core_web 2.24.1 (3.1.1 available)
  firebase_crashlytics 4.3.10 (5.0.2 available)
  firebase_crashlytics_platform_interface 3.8.10 (3.8.13 available)
  firebase_messaging 15.2.10 (16.0.2 available)
  firebase_messaging_platform_interface 4.6.10 (4.7.2 available)
  firebase_messaging_web 3.10.10 (4.0.2 available)
  firebase_remote_config 5.5.0 (6.0.2 available)
  firebase_remote_config_platform_interface 2.0.0 (2.0.3 available)
  firebase_remote_config_web 1.8.9 (1.8.12 available)
  flutter_dotenv 5.2.1 (6.0.0 available)
  flutter_lints 4.0.0 (6.0.0 available)
  flutter_markdown 0.7.7+1 (discontinued)
  flutter_riverpod 2.6.1 (3.0.1 available)
  flutter_secure_storage_linux 1.2.3 (2.0.1 available)
  flutter_secure_storage_macos 3.1.3 (4.0.0 available)
  flutter_secure_storage_platform_interface 1.1.2 (2.0.1 available)
  flutter_secure_storage_web 1.2.1 (2.0.0 available)
  flutter_secure_storage_windows 3.1.2 (4.0.0 available)
  go_router 14.8.1 (16.2.4 available)
  js 0.6.7 (0.7.2 available)
  lints 4.0.0 (6.0.0 available)
  material_color_utilities 0.11.1 (0.13.0 available)
  meta 1.16.0 (1.17.0 available)
  mime 1.0.6 (2.0.0 available)
  riverpod 2.6.1 (3.0.1 available)
  test_api 0.7.6 (0.7.7 available)
Got dependencies!
1 package is discontinued.
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter run -d emulat
or-5554    # eller det device-id du ser i `flutter devices`
Launching lib/main.dart on sdk gphone64 x86 64 in debug mode...
Running Gradle task 'assembleDebug'...
warning: [options] source value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] target value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] To suppress warnings about obsolete options, use -Xlint:-options.
Running Gradle task 'assembleDebug'...
3 warnings
Running Gradle task 'assembleDebug'...
warning: [options] source value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] target value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] To suppress warnings about obsolete options, use -Xlint:-options.
Running Gradle task 'assembleDebug'...
3 warnings
Running Gradle task 'assembleDebug'...
Note: Some input files use or override a deprecated API.
Running Gradle task 'assembleDebug'...
Note: Recompile with -Xlint:deprecation for details.
Running Gradle task 'assembleDebug'...                             29.5s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...        1,292ms
D/FlutterJNI( 6981): Beginning load of flutter...
D/FlutterJNI( 6981): flutter (null) was loaded normally!
I/flutter ( 6981): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
E/OpenGLRenderer( 6981): Unable to match the desired swap behavior.
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: PlatformException(flutter_stripe initialization failed, The plugin failed to initialize:
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): Your theme isn't set to use Theme.AppCompat or Theme.MaterialComponents.
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): Please make sure you follow all the steps detailed inside the README: https://github.com/flutter-stripe/flutter_stripe#android
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): If you continue to have trouble, follow this discussion to get some support https://github.com/flutter-stripe/flutter_stripe/discussions/538, null, null)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): #0      JSONMethodCodec.decodeEnvelope (package:flutter/src/services/message_codecs.dart:168:7)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): #1      MethodChannel._invokeMethod (package:flutter/src/services/platform_channel.dart:367:18)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): <asynchronous suspension>
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): #2      MethodChannelStripe.initialise (package:stripe_platform_interface/src/method_channel_stripe.dart:57:5)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): <asynchronous suspension>
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): #3      Stripe._initialise (package:flutter_stripe/src/stripe.dart:722:5)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): <asynchronous suspension>
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): #4      main (package:wisdom/main.dart:54:5)
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981): <asynchronous suspension>
Syncing files to device sdk gphone64 x86 64...
E/flutter ( 6981):
Syncing files to device sdk gphone64 x86 64...                     528ms

Flutter run key commands.
r Hot reload. 🔥🔥🔥
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application
running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on sdk gphone64 x86 64 is available at:
http://127.0.0.1:41185/PVTKtvC5ddk=/
The Flutter DevTools debugger and profiler on sdk gphone64 x86
64 is available at:
http://127.0.0.1:9101?uri=http://127.0.0.1:41185/PVTKtvC5ddk=/
D/ProfileInstaller( 6981): Installing profile for com.example.andlig_app

Application finished.
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$





     -x-x--x-x--x-x--x--x-x--x-x--x-x--x--x-x--x-x--x-






















    oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter run -d emulator-5554
Resolving dependencies...
Downloading packages...
  _flutterfire_internals 1.3.59 (1.3.62 available)
  characters 1.4.0 (1.4.1 available)
  crypto 3.0.6 (from transitive dependency to direct dependency)
  file_picker 8.3.7 (10.3.3 available)
  firebase_analytics 11.6.0 (12.0.2 available)
  firebase_analytics_platform_interface 4.4.3 (5.0.2 available)
  firebase_analytics_web 0.5.10+16 (0.6.0+2 available)
  firebase_core 3.15.2 (4.1.1 available)
  firebase_core_web 2.24.1 (3.1.1 available)
  firebase_crashlytics 4.3.10 (5.0.2 available)
  firebase_crashlytics_platform_interface 3.8.10 (3.8.13 available)
  firebase_messaging 15.2.10 (16.0.2 available)
  firebase_messaging_platform_interface 4.6.10 (4.7.2 available)
  firebase_messaging_web 3.10.10 (4.0.2 available)
  firebase_remote_config 5.5.0 (6.0.2 available)
  firebase_remote_config_platform_interface 2.0.0 (2.0.3 available)
  firebase_remote_config_web 1.8.9 (1.8.12 available)
  flutter_dotenv 5.2.1 (6.0.0 available)
  flutter_lints 4.0.0 (6.0.0 available)
  flutter_markdown 0.7.7+1 (discontinued)
  flutter_riverpod 2.6.1 (3.0.1 available)
  flutter_secure_storage_linux 1.2.3 (2.0.1 available)
  flutter_secure_storage_macos 3.1.3 (4.0.0 available)
  flutter_secure_storage_platform_interface 1.1.2 (2.0.1 available)
  flutter_secure_storage_web 1.2.1 (2.0.0 available)
  flutter_secure_storage_windows 3.1.2 (4.0.0 available)
  go_router 14.8.1 (16.2.4 available)
  js 0.6.7 (0.7.2 available)
  lints 4.0.0 (6.0.0 available)
  material_color_utilities 0.11.1 (0.13.0 available)
  meta 1.16.0 (1.17.0 available)
  path_provider 2.1.5 (from transitive dependency to direct dependency)
  riverpod 2.6.1 (3.0.1 available)
  test_api 0.7.6 (0.7.7 available)
Changed 2 dependencies!
1 package is discontinued.
31 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Launching lib/main.dart on sdk gphone64 x86 64 in debug mode...
Running Gradle task 'assembleDebug'...
lib/features/community/presentation/profile_edit_page.dart:118:51: Error: The getter 'mimeType' isn't defined for the type 'PlatformFile'.
Running Gradle task 'assembleDebug'...
 - 'PlatformFile' is from 'package:file_picker/src/platform_file.dart' ('../.pub-cache/hosted/pub.dev/file_picker-8.3.7/lib/src/platform_file.dart').
Running Gradle task 'assembleDebug'...
Try correcting the name to the name of an existing getter, or defining a getter or field named 'mimeType'.
Running Gradle task 'assembleDebug'...
      final contentType = _detectContentType(file.mimeType, file.name);
Running Gradle task 'assembleDebug'...
                                                  ^^^^^^^^
Running Gradle task 'assembleDebug'...
Target kernel_snapshot_program failed: Exception
Running Gradle task 'assembleDebug'...

Running Gradle task 'assembleDebug'...

Running Gradle task 'assembleDebug'...
FAILURE: Build failed with an exception.
Running Gradle task 'assembleDebug'...

Running Gradle task 'assembleDebug'...
* What went wrong:
Running Gradle task 'assembleDebug'...
Execution failed for task ':app:compileFlutterBuildDebug'.
Running Gradle task 'assembleDebug'...
> Process 'command '/home/oden/flutter/bin/flutter'' finished with non-zero exit value 1
Running Gradle task 'assembleDebug'...

Running Gradle task 'assembleDebug'...
* Try:
Running Gradle task 'assembleDebug'...
> Run with --stacktrace option to get the stack trace.
Running Gradle task 'assembleDebug'...
> Run with --info or --debug option to get more log output.
Running Gradle task 'assembleDebug'...
> Run with --scan to get full insights.
Running Gradle task 'assembleDebug'...
> Get more help at https://help.gradle.org.
Running Gradle task 'assembleDebug'...

Running Gradle task 'assembleDebug'...
BUILD FAILED in 6s
Running Gradle task 'assembleDebug'...                              6.5s
Error: Gradle task assembleDebug failed with exit code 1
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$





    -x-x--x-x--x-x--x--x-x--x-x--x-x--x--x-x--x-x--x-






















    .venv) oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ emulator -avd Pixel_7_API34
INFO         | Android emulator version 36.1.9.0 (build_id 13823996) (CL:N/A)
INFO         | Graphics backend: gfxstream
INFO         | Found systemPath /home/oden/Android/Sdk/system-images/android-34/google_apis/x86_64/
INFO         | Increasing RAM size to 2048MB
INFO         | Guest GLES Driver: Auto (ext controls)
library_mode host gpu mode host
INFO         | emuglConfig_get_vulkan_hardware_gpu_support_info: Found physical GPU 'Intel(R) Graphics (ARL)', type: VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU, apiVersion: 1.4.305, driverVersion: 25.0.7

INFO         | emuglConfig_get_vulkan_hardware_gpu_support_info: Found physical GPU 'llvmpipe (LLVM 20.1.2, 256 bits)', type: VK_PHYSICAL_DEVICE_TYPE_CPU, apiVersion: 1.4.305, driverVersion: 0.0.1

INFO         | Enabled VulkanAllocateHostMemory feature for gpu vendor Intel(R) Graphics (ARL) on Linux

INFO         | GPU device local memory = 7697MB
INFO         | Checking system compatibility:
INFO         |   Checking: hasSufficientDiskSpace
INFO         |      Ok: Disk space requirements to run avd: `Pixel_7_API34` are met
INFO         |   Checking: hasSufficientHwGpu
INFO         |      Ok: Hardware GPU requirements to run avd: `Pixel_7_API34` are passed
INFO         |   Checking: hasSufficientSystem
INFO         |      Ok: System requirements to run avd: `Pixel_7_API34` are met
WARNING      | Failed to process .ini file /home/oden/.android/avd/../avd/Pixel_7_API34.avd/quickbootChoice.ini for reading.
INFO         | Warning: Could not find the Qt platform plugin "wayland" in "/home/oden/Android/Sdk/emulator/lib64/qt/plugins" (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_btn_xr_environment_living_room_day_clicked() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_btn_xr_environment_living_room_night_clicked() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_new_posture_requested(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_posture_selection_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_new_resizable_requested(PresetEmulatorSizeType) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_resizable_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_xr_environment_mode_changed(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_xr_environment_mode_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_xr_input_mode_changed(int) (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_dismiss_xr_input_mode_dialog() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_sleep_timer_done() (:0, )
INFO         | Warning: QMetaObject::connectSlotsByName: No matching signal for on_unfold_timer_done() (:0, )
INFO         | Storing crashdata in: /tmp/android-oden/emu-crash-36.1.9.db, detection is enabled for process: 353433
INFO         | Initializing hardware OpenGLES emulation support
I1007 01:48:28.420273  353433 opengles.cpp:291] android_startOpenglesRenderer: gpu info
I1007 01:48:28.420322  353433 opengles.cpp:292]
INFO         | HealthMonitor disabled.
INFO         | SharedLibrary::open for [libvulkan.so]
INFO         | SharedLibrary::open for [libvulkan.so]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libvulkan.so] (posix): begin
INFO         | SharedLibrary::open for [libvulkan.so] (posix,linux): call dlopen on [libvulkan.so]
INFO         | SharedLibrary::open succeeded for [libvulkan.so].
INFO         | Added library: libvulkan.so
INFO         | Selecting Vulkan device: Intel(R) Graphics (ARL), Version: 1.4.305
INFO         | Disabling sparse binding feature support
INFO         | SharedLibrary::open for [libX11]
INFO         | SharedLibrary::open for [libX11]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libX11] (posix): begin
INFO         | SharedLibrary::open for [libX11] (posix,linux): call dlopen on [libX11.so]
INFO         | SharedLibrary::open succeeded for [libX11].
INFO         | SharedLibrary::open for [libGL.so.1]
INFO         | SharedLibrary::open for [libGL.so.1]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libGL.so.1] (posix): begin
INFO         | SharedLibrary::open for [libGL.so.1] (posix,linux): call dlopen on [libGL.so.1]
INFO         | SharedLibrary::open succeeded for [libGL.so.1].
INFO         | SharedLibrary::open for [libshadertranslator.so]: not found in map, open for the first time
INFO         | SharedLibrary::open for [libshadertranslator.so] (posix): begin
INFO         | SharedLibrary::open for [libshadertranslator.so] (posix,linux): call dlopen on [libshadertranslator.so]
INFO         | SharedLibrary::open succeeded for [libshadertranslator.so].
INFO         | Initializing VkEmulation features:
INFO         |     glInteropSupported: false
INFO         |     useDeferredCommands: true
INFO         |     createResourceWithRequirements: true
INFO         |     useVulkanComposition: false
INFO         |     useVulkanNativeSwapchain: false
INFO         |     enable guestRenderDoc: false
INFO         |     ASTC LDR emulation mode: Gpu
INFO         |     enable ETC2 emulation: true
INFO         |     enable Ycbcr emulation: false
INFO         |     guestVulkanOnly: false
INFO         |     useDedicatedAllocations: false
INFO         | Graphics Adapter Vendor Google (Intel)
INFO         | Graphics Adapter Android Emulator OpenGL ES Translator (Mesa Intel(R) Graphics (ARL))
INFO         | Graphics API Version OpenGL ES 3.0 (4.6 (Core Profile) Mesa 25.0.7-0ubuntu0.24.04.2)
INFO         | Graphics API Extensions GL_OES_EGL_sync GL_OES_EGL_image GL_OES_EGL_image_external GL_OES_depth24 GL_OES_depth32 GL_OES_element_index_uint GL_OES_texture_float GL_OES_texture_float_linear GL_OES_compressed_paletted_texture GL_OES_compressed_ETC1_RGB8_texture GL_OES_depth_texture GL_OES_texture_half_float GL_OES_texture_half_float_linear GL_OES_packed_depth_stencil GL_OES_vertex_half_float GL_OES_texture_npot GL_OES_rgb8_rgba8 GL_EXT_color_buffer_float GL_EXT_color_buffer_half_float GL_EXT_texture_format_BGRA8888 GL_APPLE_texture_format_BGRA8888
INFO         | Graphics Device Extensions N/A
INFO         | Sending adb public key [QAAAAL/NZbvB3d4WH2VeLgo1ktwstBTBV9+lM2i6pSkQoyp2venwXbWJrPaZ8ev594f+7NioRoB+b+9OHCtkU6/fKHxUExFyIAfHJ5Hq1pNK6umaV3p6wKUHDwKxDrxypy/d7c+6utPNWFSOpPxnwLq8SLkfWaDFk6znlHsM+XfA1n39M4wBdyZA1JWuGZNy/U5j0OCB9nihLweahlFSbYbEw7XPDsk9p7NZbI1OsdLJJSxfDZoVwJAqOGGj1l6AjyZT9mssbLJvM4osKmlnA7WiyE4KfccVzZ7v2gCKZQcYH2WJgby0sCuGCYD/vHq221FCGsptQrn67S0FhZEVOVgZ/jI4N8Ohaia9t3eJq0pS1pCRRlRmUg+9WoirHKllfpm/xj6DM2DedaHRqyatGtyjxIoXTqUJtmtD3Y5lQPaS1Oss0xcjLZ9Uqby/C0X5CLONn10bG4F/SDxbWbww8zlBVMk042nPc/0/e/mukF8vDm90AsVOqTOLY8do18+yO8AhVB9K2ve2O7l8sqTg5rkXoos5MHd026S/hHjkbkx9Ed6zp8LHyN+6t56px2O9KmhjikWgVxygPGPY/Zob2qkHlqogtMbv0LWN8ifu9kLi8mXXC1t4DTFFWnSzwIhqg4/uoHEUnGLAlbNtzmjvdvL0TGOqq/MKwJ7iB+BPfBW/dK7BKg6sbgEAAQA= oden@unknown]
I1007 01:48:28.501582  353433 userspace-boot-properties.cpp:766] Userspace boot properties:
I1007 01:48:28.501587  353433 userspace-boot-properties.cpp:770]   androidboot.boot_devices=pci0000:00/0000:00:03.0 pci0000:00/0000:00:06.0
I1007 01:48:28.501591  353433 userspace-boot-properties.cpp:770]   androidboot.dalvik.vm.heapsize=512m
I1007 01:48:28.501593  353433 userspace-boot-properties.cpp:770]   androidboot.debug.hwui.renderer=skiagl
I1007 01:48:28.501595  353433 userspace-boot-properties.cpp:770]   androidboot.hardware=ranchu
I1007 01:48:28.501597  353433 userspace-boot-properties.cpp:770]   androidboot.hardware.gltransport=pipe
I1007 01:48:28.501599  353433 userspace-boot-properties.cpp:770]   androidboot.hardware.vulkan=ranchu
I1007 01:48:28.501600  353433 userspace-boot-properties.cpp:770]   androidboot.logcat=*:V
I1007 01:48:28.501601  353433 userspace-boot-properties.cpp:770]   androidboot.opengles.version=196609
I1007 01:48:28.501603  353433 userspace-boot-properties.cpp:770]   androidboot.qemu=1
I1007 01:48:28.501604  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.adb.pubkey=QAAAAL/NZbvB3d4WH2VeLgo1ktwstBTBV9+lM2i6pSkQoyp2venwXbWJrPaZ8ev594f+7NioRoB+b+9OHCtkU6/fKHxUExFyIAfHJ5Hq1pNK6umaV3p6wKUHDwKxDrxypy/d7c+6utPNWFSOpPxnwLq8SLkfWaDFk6znlHsM+XfA1n39M4wBdyZA1JWuGZNy/U5j0OCB9nihLweahlFSbYbEw7XPDsk9p7NZbI1OsdLJJSxfDZoVwJAqOGGj1l6AjyZT9mssbLJvM4osKmlnA7WiyE4KfccVzZ7v2gCKZQcYH2WJgby0sCuGCYD/vHq221FCGsptQrn67S0FhZEVOVgZ/jI4N8Ohaia9t3eJq0pS1pCRRlRmUg+9WoirHKllfpm/xj6DM2DedaHRqyatGtyjxIoXTqUJtmtD3Y5lQPaS1Oss0xcjLZ9Uqby/C0X5CLONn10bG4F/SDxbWbww8zlBVMk042nPc/0/e/mukF8vDm90AsVOqTOLY8do18+yO8AhVB9K2ve2O7l8sqTg5rkXoos5MHd026S/hHjkbkx9Ed6zp8LHyN+6t56px2O9KmhjikWgVxygPGPY/Zob2qkHlqogtMbv0LWN8ifu9kLi8mXXC1t4DTFFWnSzwIhqg4/uoHEUnGLAlbNtzmjvdvL0TGOqq/MKwJ7iB+BPfBW/dK7BKg6sbgEAAQA= oden@unknown
I1007 01:48:28.501611  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.avd_name=Pixel_7_API34
I1007 01:48:28.501612  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.camera_hq_edge_processing=0
I1007 01:48:28.501614  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.camera_protocol_ver=1
I1007 01:48:28.501614  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.cpuvulkan.version=4202496
I1007 01:48:28.501616  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.gltransport.drawFlushInterval=800
I1007 01:48:28.501617  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.gltransport.name=pipe
I1007 01:48:28.501619  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.avcdec=2
I1007 01:48:28.501620  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.hevcdec=2
I1007 01:48:28.501622  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.hwcodec.vpxdec=2
I1007 01:48:28.501623  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.settings.system.screen_off_timeout=2147483647
I1007 01:48:28.501625  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.virtiowifi=1
I1007 01:48:28.501626  353433 userspace-boot-properties.cpp:770]   androidboot.qemu.vsync=60
I1007 01:48:28.501628  353433 userspace-boot-properties.cpp:770]   androidboot.serialno=EMULATOR36X1X9X0
I1007 01:48:28.501629  353433 userspace-boot-properties.cpp:770]   androidboot.vbmeta.digest=451e57ed688ff746d2c636d52169ade253e2bc5bb30a5c3ff23679ca15d3bcd3
I1007 01:48:28.501633  353433 userspace-boot-properties.cpp:770]   androidboot.vbmeta.hash_alg=sha256
I1007 01:48:28.501634  353433 userspace-boot-properties.cpp:770]   androidboot.vbmeta.size=6656
I1007 01:48:28.501635  353433 userspace-boot-properties.cpp:770]   androidboot.veritymode=enforcing
INFO         | Monitoring duration of emulator setup.
WARNING      | The emulator now requires a signed jwt token for gRPC access! Use the -grpc flag if you really want an open unprotected grpc port
INFO         | Using security allow list from: /home/oden/Android/Sdk/emulator/lib/emulator_access.json
WARNING      | *** Basic token auth should only be used by android-studio ***
INFO         | The active JSON Web Key Sets can be found here: /run/user/1000/avd/running/353433/jwks/e91b85dc-1664-4d73-b94f-3928c748bfd9/active.jwk
INFO         | Scanning /run/user/1000/avd/running/353433/jwks/e91b85dc-1664-4d73-b94f-3928c748bfd9 for jwk keys.
INFO         | Started GRPC server at 127.0.0.1:8554, security: Local, auth: +token
INFO         | Advertising in: /run/user/1000/avd/running/pid_353433.ini
INFO         | Setting display: 0 configuration to: 1080x2400, dpi: 420x420
INFO         | setDisplayActiveConfig 0
INFO         | Checking system compatibility:
INFO         |   Checking: hasSufficientDiskSpace
INFO         |      Ok: Disk space requirements to run avd: `Pixel_7_API34` are met
INFO         |   Checking: hasSufficientHwGpu
INFO         |      Ok: Hardware GPU requirements to run avd: `Pixel_7_API34` are passed
INFO         |   Checking: hasSufficientSystem
INFO         |      Ok: System requirements to run avd: `Pixel_7_API34` are met
INFO         | OpenGL Vendor=[Google (Intel)]
INFO         | OpenGL Renderer=[Android Emulator OpenGL ES Translator (Mesa Intel(R) Graphics (ARL))]
INFO         | OpenGL Version=[OpenGL ES 3.0 (4.6 (Core Profile) Mesa 25.0.7-0ubuntu0.24.04.2)]
INFO         | Loading snapshot 'default_boot'...
WARNING      | Failed to process .ini file /home/oden/.android/emu-update-last-check.ini for reading.
WARNING      | Device 'cache' does not have the requested snapshot 'default_boot'

WARNING      | Failed to load snapshot 'default_boot'
WARNING      | adb command '/home/oden/Android/Sdk/platform-tools/adb -s emulator-5554 shell am start-foreground-service -e meter on com.android.emulator.radio.config/.MeterService ' failed: 'adb: device offline'
WARNING      | Failed to process .ini file /home/oden/.android/emu-update-last-check.ini for reading.

-x-x--x-x--x-x--x-x--x-x--x-x--x-x--x-x--x--x-x--x-x-

oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter devices
Found 3 connected devices:
  sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64
  • Android 14 (API 34) (emulator)
  Linux (desktop)              • linux         • linux-x64
  • Ubuntu 24.04.2 LTS 6.14.0-33-generic
  Chrome (web)                 • chrome        • web-javascript
  • Chromium 140.0.7339.207 snap

Run "flutter emulators" to list and start any available device
emulators.

If you expected another device to be detected, please run
"flutter doctor" to diagnose potential issues. You may also try
increasing the time to wait for connected devices with the
"--device-timeout" flag. Visit https://flutter.dev/setup/ for
troubleshooting tips.
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ flutter run -d emulator-5554
Resolving dependencies...
Downloading packages...
  _flutterfire_internals 1.3.59 (1.3.62 available)
  characters 1.4.0 (1.4.1 available)
  file_picker 8.3.7 (10.3.3 available)
  firebase_analytics 11.6.0 (12.0.2 available)
  firebase_analytics_platform_interface 4.4.3 (5.0.2 available)
  firebase_analytics_web 0.5.10+16 (0.6.0+2 available)
  firebase_core 3.15.2 (4.1.1 available)
  firebase_core_web 2.24.1 (3.1.1 available)
  firebase_crashlytics 4.3.10 (5.0.2 available)
  firebase_crashlytics_platform_interface 3.8.10 (3.8.13 available)
  firebase_messaging 15.2.10 (16.0.2 available)
  firebase_messaging_platform_interface 4.6.10 (4.7.2 available)
  firebase_messaging_web 3.10.10 (4.0.2 available)
  firebase_remote_config 5.5.0 (6.0.2 available)
  firebase_remote_config_platform_interface 2.0.0 (2.0.3 available)
  firebase_remote_config_web 1.8.9 (1.8.12 available)
  flutter_dotenv 5.2.1 (6.0.0 available)
  flutter_lints 4.0.0 (6.0.0 available)
  flutter_markdown 0.7.7+1 (discontinued)
  flutter_riverpod 2.6.1 (3.0.1 available)
  flutter_secure_storage_linux 1.2.3 (2.0.1 available)
  flutter_secure_storage_macos 3.1.3 (4.0.0 available)
  flutter_secure_storage_platform_interface 1.1.2 (2.0.1 available)
  flutter_secure_storage_web 1.2.1 (2.0.0 available)
  flutter_secure_storage_windows 3.1.2 (4.0.0 available)
  go_router 14.8.1 (16.2.4 available)
  js 0.6.7 (0.7.2 available)
  lints 4.0.0 (6.0.0 available)
  material_color_utilities 0.11.1 (0.13.0 available)
  meta 1.16.0 (1.17.0 available)
  riverpod 2.6.1 (3.0.1 available)
  test_api 0.7.6 (0.7.7 available)
Got dependencies!
1 package is discontinued.
31 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Launching lib/main.dart on sdk gphone64 x86 64 in debug mode...
Running Gradle task 'assembleDebug'...
Checking the license for package NDK (Side by side) 27.0.12077973 in /home/oden/Android/Sdk/licenses
Running Gradle task 'assembleDebug'...
License for package NDK (Side by side) 27.0.12077973 accepted.
Running Gradle task 'assembleDebug'...
Preparing "Install NDK (Side by side) 27.0.12077973 v.27.0.12077973".
Running Gradle task 'assembleDebug'...
"Install NDK (Side by side) 27.0.12077973 v.27.0.12077973" ready.
Running Gradle task 'assembleDebug'...
Installing NDK (Side by side) 27.0.12077973 in /home/oden/Android/Sdk/ndk/27.0.12077973
Running Gradle task 'assembleDebug'...
"Install NDK (Side by side) 27.0.12077973 v.27.0.12077973" complete.
Running Gradle task 'assembleDebug'...
"Install NDK (Side by side) 27.0.12077973 v.27.0.12077973" finished.
Running Gradle task 'assembleDebug'...
Checking the license for package Android SDK Build-Tools 35 in /home/oden/Android/Sdk/licenses
Running Gradle task 'assembleDebug'...
License for package Android SDK Build-Tools 35 accepted.
Running Gradle task 'assembleDebug'...
Preparing "Install Android SDK Build-Tools 35 v.35.0.0".
Running Gradle task 'assembleDebug'...
"Install Android SDK Build-Tools 35 v.35.0.0" ready.
Running Gradle task 'assembleDebug'...
Installing Android SDK Build-Tools 35 in /home/oden/Android/Sdk/build-tools/35.0.0
Running Gradle task 'assembleDebug'...
"Install Android SDK Build-Tools 35 v.35.0.0" complete.
Running Gradle task 'assembleDebug'...
"Install Android SDK Build-Tools 35 v.35.0.0" finished.
Running Gradle task 'assembleDebug'...
Checking the license for package Android SDK Platform 35 in /home/oden/Android/Sdk/licenses
Running Gradle task 'assembleDebug'...
License for package Android SDK Platform 35 accepted.
Running Gradle task 'assembleDebug'...
Preparing "Install Android SDK Platform 35 (revision 2)".
Running Gradle task 'assembleDebug'...
"Install Android SDK Platform 35 (revision 2)" ready.
Running Gradle task 'assembleDebug'...
Installing Android SDK Platform 35 in /home/oden/Android/Sdk/platforms/android-35
Running Gradle task 'assembleDebug'...
"Install Android SDK Platform 35 (revision 2)" complete.
Running Gradle task 'assembleDebug'...
"Install Android SDK Platform 35 (revision 2)" finished.
Running Gradle task 'assembleDebug'...
warning: [options] source value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] target value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] To suppress warnings about obsolete options, use -Xlint:-options.
Running Gradle task 'assembleDebug'...
3 warnings
Running Gradle task 'assembleDebug'...
warning: [options] source value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] target value 8 is obsolete and will be removed in a future release
Running Gradle task 'assembleDebug'...
warning: [options] To suppress warnings about obsolete options, use -Xlint:-options.
Running Gradle task 'assembleDebug'...
3 warnings
Running Gradle task 'assembleDebug'...
Note: Some input files use or override a deprecated API.
Running Gradle task 'assembleDebug'...
Note: Recompile with -Xlint:deprecation for details.
Running Gradle task 'assembleDebug'...
Checking the license for package CMake 3.22.1 in /home/oden/Android/Sdk/licenses
Running Gradle task 'assembleDebug'...
License for package CMake 3.22.1 accepted.
Running Gradle task 'assembleDebug'...
Preparing "Install CMake 3.22.1 v.3.22.1".
Running Gradle task 'assembleDebug'...
"Install CMake 3.22.1 v.3.22.1" ready.
Running Gradle task 'assembleDebug'...
Installing CMake 3.22.1 in /home/oden/Android/Sdk/cmake/3.22.1
Running Gradle task 'assembleDebug'...
"Install CMake 3.22.1 v.3.22.1" complete.
Running Gradle task 'assembleDebug'...
"Install CMake 3.22.1 v.3.22.1" finished.
Running Gradle task 'assembleDebug'...                            467.1s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...        1,683ms
D/FlutterJNI( 6506): Beginning load of flutter...
D/FlutterJNI( 6506): flutter (null) was loaded normally!
I/flutter ( 6506): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
D/FLTFireContextHolder( 6506): received application context.
W/Glide   ( 6506): Failed to find GeneratedAppGlideModule. You should include an annotationProcessor compile dependency on com.github.bumptech.glide:compiler in your application and a @GlideModule annotated AppGlideModule implementation or LibraryGlideModules will be silently ignored
W/ziparchive( 6506): Unable to open '/data/user_de/0/com.google.android.gms/app_chimera/m/00000002/DynamiteLoader.dm': No such file or directory
W/ziparchive( 6506): Unable to open '/data/user_de/0/com.google.android.gms/app_chimera/m/00000002/DynamiteLoader.dm': No such file or directory
I/DynamiteModule( 6506): Considering local module com.google.android.gms.measurement.dynamite:152 and remote module com.google.android.gms.measurement.dynamite:90
I/DynamiteModule( 6506): Selected local version of com.google.android.gms.measurement.dynamite
Syncing files to device sdk gphone64 x86 64...
W/mple.andlig_app( 6506): Accessing hidden method Landroid/view/accessibility/AccessibilityNodeInfo;->getSourceNodeId()J (unsupported,test-api, reflection, allowed)
Syncing files to device sdk gphone64 x86 64...
W/mple.andlig_app( 6506): Accessing hidden method Landroid/view/accessibility/AccessibilityRecord;->getSourceNodeId()J (unsupported, reflection, allowed)
Syncing files to device sdk gphone64 x86 64...
W/mple.andlig_app( 6506): Accessing hidden field Landroid/view/accessibility/AccessibilityNodeInfo;->mChildNodeIds:Landroid/util/LongArray; (unsupported, reflection, allowed)
Syncing files to device sdk gphone64 x86 64...
W/mple.andlig_app( 6506): Accessing hidden method Landroid/util/LongArray;->get(I)J (unsupported, reflection, allowed)
Syncing files to device sdk gphone64 x86 64...
I/FA      ( 6506): App measurement initialized, version: 130000
Syncing files to device sdk gphone64 x86 64...
I/FA      ( 6506): To enable debug logging run: adb shell setprop log.tag.FA VERBOSE
Syncing files to device sdk gphone64 x86 64...
I/FA      ( 6506): To enable faster debug mode event logging run:
Syncing files to device sdk gphone64 x86 64...
I/FA      ( 6506):   adb shell setprop debug.firebase.analytics.app com.example.andlig_app
Syncing files to device sdk gphone64 x86 64...
E/FA      ( 6506): Missing google_app_id. Firebase Analytics disabled. See https://goo.gl/NAOOOI
Syncing files to device sdk gphone64 x86 64...
E/FA      ( 6506): Uploading is not possible. App measurement disabled
Syncing files to device sdk gphone64 x86 64...
I/FA      ( 6506): Tag Manager is not found and thus will not be used
Syncing files to device sdk gphone64 x86 64...
D/CompatibilityChangeReporter( 6506): Compat change id reported: 237531167; UID 10192; state: DISABLED
Syncing files to device sdk gphone64 x86 64...
W/OpenGLRenderer( 6506): Unknown dataspace 0
Syncing files to device sdk gphone64 x86 64...
I/Choreographer( 6506): Skipped 112 frames!  The application may be doing too much work on its main thread.
Syncing files to device sdk gphone64 x86 64...
I/Gralloc4( 6506): mapper 4.x is not supported
Syncing files to device sdk gphone64 x86 64...
W/OpenGLRenderer( 6506): Failed to choose config with EGL_SWAP_BEHAVIOR_PRESERVED, retrying without...
Syncing files to device sdk gphone64 x86 64...
W/OpenGLRenderer( 6506): Failed to initialize 101010-2 format, error = EGL_SUCCESS
Syncing files to device sdk gphone64 x86 64...
E/OpenGLRenderer( 6506): Unable to match the desired swap behavior.
Syncing files to device sdk gphone64 x86 64...                     807ms

Flutter run key commands.
r Hot reload. 🔥🔥🔥
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application
running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on sdk gphone64 x86 64 is available at:
http://127.0.0.1:38423/3EwYBMigLfY=/
The Flutter DevTools debugger and profiler on sdk gphone64 x86
64 is available at:
http://127.0.0.1:9101?uri=http://127.0.0.1:38423/3EwYBMigLfY=/
E/flutter ( 6506): [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: PlatformException(flutter_stripe initialization failed, The plugin failed to initialize:
E/flutter ( 6506): Your Main Activity class com.example.andlig_app.MainActivity is not a subclass FlutterFragmentActivity.
E/flutter ( 6506): Please make sure you follow all the steps detailed inside the README: https://github.com/flutter-stripe/flutter_stripe#android
E/flutter ( 6506): If you continue to have trouble, follow this discussion to get some support https://github.com/flutter-stripe/flutter_stripe/discussions/538, null, null)
E/flutter ( 6506): #0      JSONMethodCodec.decodeEnvelope (package:flutter/src/services/message_codecs.dart:168:7)
E/flutter ( 6506): #1      MethodChannel._invokeMethod (package:flutter/src/services/platform_channel.dart:367:18)
E/flutter ( 6506): <asynchronous suspension>
E/flutter ( 6506): #2      MethodChannelStripe.initialise (package:stripe_platform_interface/src/method_channel_stripe.dart:57:5)
E/flutter ( 6506): <asynchronous suspension>
E/flutter ( 6506): #3      Stripe._initialise (package:flutter_stripe/src/stripe.dart:722:5)
E/flutter ( 6506): <asynchronous suspension>
E/flutter ( 6506): #4      main (package:wisdom/main.dart:54:5)
E/flutter ( 6506): <asynchronous suspension>
E/flutter ( 6506):
I/Choreographer( 6506): Skipped 67 frames!  The application may be doing too much work on its main thread.
D/ProfileInstaller( 6506): Installing profile for com.example.andlig_app




