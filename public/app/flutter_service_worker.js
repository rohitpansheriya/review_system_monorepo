'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "ffd9b356c3fd7ab3060cbacff350b40d",
"version.json": "9f9cbb400ca9e5d449968d9b44c421d2",
"index.html": "4edef83fd2ecac995b8d24311a815d3f",
"/": "4edef83fd2ecac995b8d24311a815d3f",
"apple-touch-icon.png": "386f0874ba583ba21f7a5fe6023c21e2",
"main.dart.js": "31cdd235e86e7afd0d24e8ecf7bce04d",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"favicon.png": "e680f4fb0eafdece43f46b2fc78ce7ad",
"icons/Icon-192.png": "39fe29904463cb194ec4a62f85519b73",
"icons/Icon-maskable-192.png": "688915c7fd1b0f653fa7a4557eef64cc",
"icons/Icon-maskable-512.png": "30fcacb549d5c0309d412f6461495563",
"icons/Icon-512.png": "87153ef0223ab005a9601da69de4ea0b",
"manifest.json": "71745dbf3d413975649e444a6b39a4e3",
"firebase-config.js": "9ab025ec7b614cb50b08e4ece4d9f1a7",
"assets/AssetManifest.json": "ab1f1e9b67ac278db0a1a3a2b305d413",
"assets/NOTICES": "0e77bc2050fcef87a71976522dd33b97",
"assets/FontManifest.json": "7b2a36307916a9721811788013e65289",
"assets/AssetManifest.bin.json": "a09e592e1d2d837534fd77853ccc66c3",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "c8b5e3cd19a3f2ff7c40d1644978b6b4",
"assets/fonts/MaterialIcons-Regular.otf": "2ffd4d8c6d33d50bdf57fac2c760e5d6",
"assets/assets/images/favicon-16x16.png": "50c2845197ae4590f95145ac31a52c68",
"assets/assets/images/favicon.ico": "c30d0dc35f032f675b860c896f030897",
"assets/assets/images/rohit-profile.jpg": "ec14ce69243fc393fc33552b2e0b6cbe",
"assets/assets/images/apple-touch-icon.png": "386f0874ba583ba21f7a5fe6023c21e2",
"assets/assets/images/Icon-192.png": "39fe29904463cb194ec4a62f85519b73",
"assets/assets/images/appnexa-icon-white.png": "de895299b84c18055e53c87e88a910e3",
"assets/assets/images/Icon-maskable-192.png": "688915c7fd1b0f653fa7a4557eef64cc",
"assets/assets/images/appnexa-icon.png": "f6b5dd45be20a9b590eda38a269da86b",
"assets/assets/images/appnexa-logo-black.png": "499b7c93087c7cc7fdf13fcc52c0519f",
"assets/assets/images/appnexa-logo-full.png": "6a9327492dca1db0a0d59e2e11789f84",
"assets/assets/images/favicon-48x48.png": "43d440a59bec29a60e4219c4bb4a63d8",
"assets/assets/images/favicon.png": "e680f4fb0eafdece43f46b2fc78ce7ad",
"assets/assets/images/appnexa-logo-tagline.png": "173934ea59bbe63bc0bf476e01071399",
"assets/assets/images/appnexa-icon-black.png": "0badc3b1f71bbdefc5769b6e5a2200e0",
"assets/assets/images/Icon-maskable-512.png": "30fcacb549d5c0309d412f6461495563",
"assets/assets/images/appnexa-logo-white.png": "6d274c171d568f000ecd73040e89d315",
"assets/assets/images/Icon-512.png": "87153ef0223ab005a9601da69de4ea0b",
"assets/assets/images/favicon-32x32.png": "e680f4fb0eafdece43f46b2fc78ce7ad",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
