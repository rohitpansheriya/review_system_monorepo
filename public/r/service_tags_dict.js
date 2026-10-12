const GLOBAL_SERVICE_TAGS_MAP = {
  "🍕 Wood-fired Pizza": [
    "🔥 Crispy Smoky Crust",
    "🧀 Rich Gooey Cheese",
    "🍅 Fresh Basil Marinara",
    "🍕 Authentic Italian Taste",
    "🌿 Fresh Garden Toppings",
    "🔥 Served Sizzling Hot",
    "👌 Perfect Thin Base"
  ],
  "🍝 Creamy Pasta": [
    "🍝 Rich Creamy Alfredo Sauce",
    "🧀 Perfectly Cooked Al Dente",
    "🌿 Fragrant Italian Herbs",
    "🥖 Generous Portion Size",
    "😋 Deliciously Balanced Seasoning",
    "🔥 Served Steaming Hot"
  ],
  "🥖 Garlic Bread": [
    "🥖 Golden Crunchy Crust",
    "🧈 Rich Garlic Butter",
    "🧀 Warm Melted Cheese",
    "😋 Great Flavor Kick",
    "👌 Perfect Crispy Starter",
    "🌿 Fresh Parsley Touch"
  ],
  "🍹 Mocktails": [
    "🍹 Refreshing Mint & Citrus",
    "🍋 Perfectly Chilled & Crisp",
    "✨ Beautiful Glass Presentation",
    "😋 Balanced Sweetness",
    "🍓 Real Fruit Infusions",
    "🧊 Super Energizing"
  ],
  "🧀 Lasagna": [
    "🧀 Multi-Layered Melted Cheese",
    "🍅 Rich Savory Sauce",
    "😋 Baked to Golden Perfection",
    "🔥 Tender Pasta Sheets",
    "👌 Hearty & Very Filling",
    "🌿 Authentic Italian Recipe"
  ],
  "🥗 Caesar Salad": [
    "🥗 Crisp Crunchy Lettuce",
    "🧀 Creamy Parmesan Dressing",
    "🥖 Crispy Toasted Croutons",
    "🌿 Farm Fresh Greens",
    "👌 Light & Refreshing",
    "😋 Perfectly Tossed"
  ],
  "☕ Cappuccino": [
    "☕ Silky Micro-Foam",
    "✨ Beautiful Latte Art",
    "😋 Rich Roasted Beans",
    "🔥 Perfect Drinking Temperature",
    "👌 Bold Espresso Taste",
    "🌿 Smooth Non-Bitter Finish"
  ],
  "🧊 Iced Latte": [
    "🧊 Smooth Creamy Milk",
    "☕ Bold Espresso Shot",
    "❄️ Perfectly Chilled",
    "😋 Refreshing & Energizing",
    "👌 Balanced Sweetness",
    "🥤 Great Takeaway Cup"
  ],
  "🥐 Butter Croissant": [
    "🥐 Flaky Golden Layers",
    "🧈 Rich French Butter Flavor",
    "🔥 Warm & Oven Fresh",
    "😋 Light & Airy Texture",
    "👌 Melts in the Mouth",
    "☕ Perfect with Coffee"
  ],
  "🥤 Cold Brew": [
    "🥤 Slow-Steeped 18 Hours",
    "☕ Naturally Smooth & Sweet",
    "🧊 Low Acidity Crispness",
    "😋 Bold Caffeine Kick",
    "👌 Clean Flavor Profile",
    "🌿 Premium Roast"
  ],
  "🥪 Grilled Panini": [
    "🥪 Golden Toasted Focaccia",
    "🧀 Melted Mozzarella Stretch",
    "🍅 Fresh Grilled Veggies",
    "😋 Tangy Herb Spread",
    "🔥 Served Hot & Crunchy",
    "👌 Hearty Portion"
  ],
  "🥑 Avocado Toast": [
    "🥑 Fresh Creamy Ripe Avocado",
    "🥖 Toasted Artisanal Sourdough",
    "🌶️ Chilly Flakes & Feta Sprinkle",
    "🍋 Zesty Lemon Squeeze",
    "👌 Super Healthy & Fresh",
    "✨ Aesthetic Cafe Plating"
  ],
  "🎂 Custom Celebration Cake": [
    "🎨 Stunning Custom Design",
    "🍰 Super Soft Moist Sponge",
    "✨ Perfectly Balanced Sweetness",
    "🥛 Fresh Dairy Frosting",
    "👌 Exact Photo Match",
    "📦 Secure Strong Box",
    "🎉 Party Showstopper"
  ],
  "🧁 Cupcakes & Tarts": [
    "🧁 Silky Smooth Buttercream",
    "🍓 Fresh Fruit Toppings",
    "😋 Fluffy Moist Sponge",
    "👌 Crispy Tart Shell",
    "✨ Beautifully Decorated",
    "🍫 Rich Chocolate Center"
  ],
  "🥖 Sourdough Breads": [
    "🥖 Crusty Golden Exterior",
    "🌾 Soft Airy Crumb Structure",
    "😋 Authentic Fermented Tang",
    "🍞 100% Artisan Flour",
    "👌 Oven Fresh Daily",
    "🧈 Perfect with Butter"
  ],
  "🍰 Pastry Slices": [
    "🍰 Melt-in-Mouth Layers",
    "🍫 Premium Belgian Chocolate",
    "✨ Rich Velvet Cream",
    "😋 Not Overly Sweet",
    "👌 Freshly Baked Slices",
    "🍓 Generous Fruit Glaze"
  ],
  "🍪 Cookies & Macarons": [
    "🍪 Chewy Chocolate Center",
    "✨ Delicate Crispy Macaron Shell",
    "🧈 Rich Butter Aroma",
    "😋 Delightful Ganache Filling",
    "👌 Fresh Batch Baked",
    "🎁 Elegant Gift Box"
  ],
  "🍔 Gourmet Burger": [
    "🍔 Soft Brioche Bun",
    "🥩 Juicy Tender Patty",
    "🧀 Gooey Melted Cheddar",
    "🥫 Signature Secret Sauce",
    "🥬 Crisp Lettuce & Pickles",
    "🔥 Served Piping Hot",
    "👌 Big Generous Size"
  ],
  "🍟 Loaded Cheese Fries": [
    "🍟 Ultra Crispy Golden Fries",
    "🧀 Warm Cheese Sauce Drizzle",
    "🌶️ Spicy Jalapeno Bits",
    "🔥 Served Hot & Crunchy",
    "😋 Irresistible Finger Food",
    "👌 Super Generous Portion"
  ],
  "🍗 Crispy Fried Chicken": [
    "🍗 Extra Crunchy Outer Crust",
    "🥩 Juicy & Tender Inside",
    "🌶️ Bold Seasoning Blend",
    "🔥 Non-Greasy Crispiness",
    "🥫 Delicious Garlic Dip",
    "👌 Freshly Fried Batch"
  ],
  "🥤 Thick Milkshake": [
    "🥤 Ultra-Rich Creamy Thickness",
    "🍫 Decadent Real Chocolate",
    "🍦 Smooth Vanilla Ice Cream Base",
    "😋 Delicious Sweet Flavor",
    "❄️ Perfectly Chilled",
    "👌 Big Tall Cup"
  ],
  "🌯 Wraps": [
    "🌯 Soft Grilled Tortilla Wrap",
    "🥩 Well-Spiced Tender Filling",
    "🥬 Crunchy Fresh Veggies",
    "🥫 Tangy Creamy Sauce",
    "👌 Easy Mess-Free Bite",
    "🔥 Freshly Rolled Hot"
  ],
  "🧀 Paneer Butter Masala": [
    "🧀 Melt-in-Mouth Fresh Paneer",
    "🍲 Rich Creamy Tomato Gravy",
    "🌿 Mild Aromatic Spices",
    "🧈 Pure Desi Ghee Finish",
    "😋 Authentic Royal Flavor",
    "👌 Perfectly Balanced Sweet & Savory"
  ],
  "🍗 Butter Chicken": [
    "🍗 Succulent Smoky Tandoori Chicken",
    "🍲 Silky Smooth Velvet Gravy",
    "🧈 Rich Butter & Cream Blend",
    "🌿 Fragrant Kasuri Methi",
    "😋 Classic Authentic Taste",
    "🔥 Served Piping Hot"
  ],
  "🫓 Garlic Butter Naan": [
    "🫓 Tandoor Baked Fluffy Naan",
    "🧄 Roasted Crispy Garlic Bits",
    "🧈 Generous Melted Butter",
    "🔥 Soft & Chewy Texture",
    "👌 Perfect Bread for Gravies",
    "😋 Fresh from Clay Oven"
  ],
  "🍲 Dal Makhani": [
    "🍲 Slow-Cooked Overnight Black Lentils",
    "🧈 Creamy Velvet Texture",
    "🌿 Smoky Dhungar Aroma",
    "😋 Rich Traditional Taste",
    "👌 Comfort Food at its Best",
    "🔥 Served Hot with Butter"
  ],
  "🍢 Tandoori Platter": [
    "🍢 Smoky Charred Marinade",
    "🍋 Zesty Mint Chutney Pairing",
    "🥩 Juicy Tender Kebabs",
    "🌶️ Perfectly Spiced Rub",
    "🔥 Sizzling Hot Presentation",
    "👌 Huge Assorted Variety"
  ],
  "🍚 Dum Biryani": [
    "🍚 Extra-Long Basmati Rice",
    "🌿 Fragrant Dum Saffron Aroma",
    "🥩 Tender Fall-off-Bone Meat",
    "🌶️ Rich Layered Masala",
    "🧈 Pure Ghee Preparation",
    "🔥 Served Steaming Hot",
    "👌 Authentic Hyderabadi Touch"
  ],
  "🍗 Chicken Biryani": [
    "🍗 Juicy Marinated Chicken Pieces",
    "🍚 Fluffy Non-Sticky Basmati Rice",
    "🌿 Fresh Mint & Fried Onions",
    "🌶️ Perfectly Balanced Heat",
    "😋 Deep Rich Spice Flavor",
    "👌 Very Generous Serving"
  ],
  "🧀 Paneer Biryani": [
    "🧀 Soft Well-Marinated Paneer Cubes",
    "🍚 Aromatic Long-Grain Rice",
    "🌿 Fragrant Whole Spices",
    "😋 Rich Layered Veg Masala",
    "👌 Non-Greasy & Flavorful",
    "🔥 Served Fresh & Hot"
  ],
  "🥣 Mirchi Ka Salan": [
    "🥣 Rich Peanut & Sesame Gravy",
    "🌶️ Mild Bhavnagri Chilies",
    "😋 Tangy Tamarind Balance",
    "👌 Perfect Biryani Accompaniment",
    "🌿 Authentic Traditional Recipe",
    "🍲 Thick Delicious Consistency"
  ],
  "🍢 Kebabs": [
    "🍢 Smoky Charcoal Grilled",
    "🥩 Tender & Juicy Inside",
    "🌿 Fresh Green Chutney",
    "🌶️ Perfectly Spiced Marinade",
    "🔥 Served Sizzling Hot",
    "👌 Great Starter Platter"
  ],
  "🥞 Crispy Masala Dosa": [
    "🔥 Paper-Thin Golden Crust",
    "🥔 Flavorful Potato Masala",
    "🧈 Rich Pure Ghee Roast",
    "🥥 Fresh Coconut Chutney",
    "🍲 Piping Hot Tangy Sambar",
    "😋 Authentic Udipi Taste",
    "👌 Huge Crispy Dosa"
  ],
  "🥟 Soft Idli & Vada Combo": [
    "🥟 Pillowy Soft Steamed Idlis",
    "🍩 Golden Crispy Medu Vada",
    "🥥 3 Fresh Varieties of Chutney",
    "🍲 Rich Lentil Sambar",
    "👌 Freshly Made Batch",
    "😋 Light & Digestible"
  ],
  "☕ Filter Coffee": [
    "☕ Frothy Kumbakonam Decoction",
    "🥛 Creamy Rich Milk",
    "✨ Served in Traditional Brass Dabara",
    "😋 Strong Aromatic Roast",
    "🔥 Piping Hot & Refreshing",
    "👌 Authentic Morning Starter"
  ],
  "🥞 Onion Uttapam": [
    "🥞 Fluffy Thick Base",
    "🧅 Caramelized Crispy Onions",
    "🌿 Fresh Coriander & Curry Leaves",
    "🧈 Ghee Roasted to Perfection",
    "🍲 Served with Warm Sambar",
    "👌 Filling & Delicious"
  ],
  "🍚 Curd Rice": [
    "🍚 Creamy Fresh Curd Blend",
    "🌿 Mustard & Curry Leaf Tadka",
    "🥒 Crunchy Pomegranate & Ginger Bits",
    "👌 Cool & Soothing Finish",
    "😋 Light on Stomach",
    "🥣 Served Fresh with Pickle"
  ],
  "🧇 Belgian Waffle": [
    "🧇 Warm & Extra Crispy",
    "🍫 Drizzled with Belgian Chocolate",
    "🍓 Fresh Strawberry Toppings",
    "🍨 Served with Vanilla Scoop",
    "😋 Fluffy Inside & Crunchy Crust",
    "👌 Freshly Baked to Order"
  ],
  "🍨 Sundae Bowl": [
    "🍨 Generous Multiple Scoops",
    "🍫 Warm Fudge & Roasted Nuts",
    "🍒 Cherry & Whipped Cream on Top",
    "😋 Indulgent Rich Flavor",
    "👌 Decadent Sweet Treat",
    "✨ Aesthetic Ice Cream Bowl"
  ],
  "🍦 Artisanal Gelato Scoops": [
    "🍦 Dense Creamy Texture",
    "🥛 100% Real Whole Milk",
    "🍓 Natural Fruit Pulp Flavors",
    "😋 Slow-Churned Smoothness",
    "👌 Perfectly Balanced Sweetness",
    "🍫 Rich Pistachio & Dark Cocoa"
  ],
  "🍫 Sizzling Brownie": [
    "🍫 Fudgy Warm Walnut Brownie",
    "🔥 Sizzling Hot Cast-Iron Plate",
    "🍨 Topped with Cold Vanilla Scoop",
    "🍫 Warm Pour-Over Chocolate Sauce",
    "😋 Heavenly Warm-Cold Contrast",
    "👌 Absolute Crowd Favorite"
  ],
  "🍧 Kulfi Falooda": [
    "🍧 Rich Malai Kulfi Slices",
    "🥛 Chilled Rose Rabdi Base",
    "🌾 Silky Soft Falooda Sev",
    "🌱 Crunchy Basil Seeds (Sabja)",
    "😋 Traditional Royal Dessert",
    "👌 Super Refreshing & Sweet"
  ],
  "🍜 Hakka Noodles": [
    "🔥 High-Flame Wok Toss",
    "🍜 Non-Sticky Long Noodles",
    "🥬 Crunchy Julienne Vegetables",
    "🌶️ Balanced Garlic Soy Flavor",
    "😋 Non-Greasy & Flavorful",
    "👌 Huge Serving Bowl"
  ],
  "🥟 Steamed Momos": [
    "🥟 Thin Translucent Dough Wrapper",
    "🥩 Juicy Tender Filling",
    "🌶️ Spicy Fiery Garlic Chutney",
    "🔥 Steaming Hot Basket",
    "😋 Bursting with Flavor",
    "👌 Handcrafted Fresh Daily"
  ],
  "🥘 Manchurian Gravy": [
    "🥘 Crispy Fried Veggie Balls",
    "🧄 Rich Garlic-Soya Gravy",
    "🌶️ Tangy Spicy Indo-Chinese Kick",
    "🌿 Fresh Spring Onion Garnish",
    "🔥 Served Piping Hot",
    "👌 Perfect Combo with Rice or Noodles"
  ],
  "🍚 Fried Rice": [
    "🍚 Separated Long-Grain Rice",
    "🥬 Fresh Finely Diced Veggies",
    "🔥 Smoky Wok-Hei Flavor",
    "😋 Perfectly Seasoned",
    "👌 Non-Oily Light Texture",
    "🥢 Classic Comfort Meal"
  ],
  "🍲 Hot & Sour Soup": [
    "🍲 Thick Warming Broth",
    "🌶️ Zesty Tangy Spicy Kick",
    "🍄 Loaded with Mushrooms & Veggies",
    "🔥 Served Steaming Hot",
    "👌 Great Appetizer Starter",
    "😋 Comforting Winter Favorite"
  ],
  "🥙 Pani Puri": [
    "💧 100% Hygienic Mineral Water",
    "🥔 Extra Crispy Golden Puris",
    "🌶️ Spicy Tangy Mint Water",
    "😋 Sweet Tamarind Chutney",
    "🥔 Warm Spiced Potato Filling",
    "👌 Unmatched Street Flavor"
  ],
  "🥔 Sev Puri & Dahi Puri": [
    "🥔 Crispy Flat Puris",
    "🥛 Chilled Creamy Sweet Dahi",
    "🌶️ Bursting with Trio Chutneys",
    "🌾 Topped with Crispy Fine Sev",
    "🌿 Fresh Pomegranate & Coriander",
    "😋 Melt-in-Mouth Chaat"
  ],
  "🥪 Cheese Grilled Sandwich": [
    "🥪 Golden Crispy Toasted Bread",
    "🧀 Overflowing Melted Amul Cheese",
    "🥔 Spiced Potato & Veggie Filling",
    "🌿 Spicy Green Chutney Spread",
    "🔥 Served Piping Hot",
    "👌 Classic Bombay Style"
  ],
  "🥟 Samosa Chaat": [
    "🥟 Crushed Hot Crispy Samosa",
    "🍲 Warm Spiced Chole Gravy",
    "🥛 Drizzled with Dahi & Chutneys",
    "🧅 Topped with Crunchy Onions & Sev",
    "😋 Lip-Smacking Street Taste",
    "👌 Super Filling Portion"
  ],
  "🫔 Pav Bhaji": [
    "🫔 Buttery Mashed Mixed Vegetable Bhaji",
    "🧈 Extra Butter Toasted Soft Pavs",
    "🧅 Fresh Lemon & Onion Rings",
    "🌶️ Authentic Mumbai Masala",
    "🔥 Served Sizzling Hot",
    "😋 Rich & Flavorful Gravy"
  ],
  "✂️ Modern Fade Haircut": [
    "✂️ Clean Seamless Skin Fade",
    "👌 Scissor Precision on Top",
    "💡 Stylist Listened to Request",
    "✨ Sharp Neckline Taper",
    "🧴 Premium Matte Clay Styling",
    "🧼 Sanitized Clippers Used",
    "👍 Modern Trendy Look"
  ],
  "🧔 Sharp Beard Styling": [
    "🧔 Laser-Sharp Razor Edges",
    "✂️ Even Beard Length Blending",
    "🧴 Soothing Aftershave Balm",
    "🔥 Warm Towel Steam Prep",
    "👌 Perfectly Shaped Cheek Lines",
    "🌿 Nourishing Beard Oil"
  ],
  "💆 Relaxing Head Massage": [
    "💆 Deep Scalp Acupressure",
    "🌿 Cooling Herbal Almond Oil",
    "✨ Instant Stress Relief",
    "👌 Relieved Neck & Shoulder Tension",
    "⏱️ Full 15-Minute Dedicated Massage",
    "🛋️ Relaxing Reclined Chair"
  ],
  "🧖 Deep Face Cleanup": [
    "🧖 Unclogged Pores & Blackheads",
    "✨ Refreshing Tan Removal Scrub",
    "🌿 Cooling Aloe Mask",
    "💧 Smooth Hydrated Face",
    "👌 Gentle Non-Irritating Touch",
    "🧼 Fresh Sterile Disposable Towel"
  ],
  "🧴 Hair Spa": [
    "🧴 Deep Conditioning Mask",
    "💨 Gentle Steam Treatment",
    "✨ Scalp Nourishment & Shine",
    "💆 Relaxing Scalp Massage",
    "👌 Silky Soft Manageable Hair",
    "🌿 Zero Frizz Finish"
  ],
  "✂️ Layered Haircut": [
    "✂️ Flawless Face-Framing Layers",
    "✨ Gorgeous Natural Bounce",
    "👌 Preserved Hair Length as Requested",
    "💨 Stunning Blowdry Finish",
    "💡 Expert Stylist Consultation",
    "💇 Great Texture & Volume"
  ],
  "🎨 Global Hair Color": [
    "🎨 Rich Uniform Color Coverage",
    "🌿 100% Ammonia-Free Gentle Formula",
    "✨ Glossy Radiant Shine",
    "👌 Perfect Gray Coverage",
    "🧴 Top International Brand Colors",
    "💆 Gentle Scalp Application"
  ],
  "✨ Balayage Highlights": [
    "✨ Seamless Sun-Kissed Blend",
    "🎨 Customized Ash Blonde / Caramel Tones",
    "🌿 Zero Harsh Bleach Lines",
    "💎 Stunning Multi-Dimensional Depth",
    "👌 Long-Lasting Salon Tone",
    "📸 High Instagrammable Finish"
  ],
  "💆 Keratin Treatment": [
    "✨ Silky Ultra-Smooth Texture",
    "💨 Completely Frizz-Free Lock",
    "🌧️ Humidity Proof Hair",
    "🌿 Restored Protein Health",
    "👌 Cut Down Daily Styling Time",
    "💎 Brilliant Glass Hair Shine"
  ],
  "🧖 Anti-frizz Botox": [
    "🧖 Deep Fiber Hydration",
    "✨ Tamed Unruly Flyaways",
    "🌿 Nourished Split Ends",
    "👌 Natural Movement Retained",
    "🧴 Safe Formaldehyde-Free Formula",
    "💎 Silky Soft Touch"
  ],
  "💆 Full Body Massage": [
    "💆 Expert Pressure on Knot Points",
    "🌿 Warm Organic Sesame / Olive Oil",
    "✨ Deep Muscle Relaxation",
    "🕯️ Calming Candlelit Therapy Room",
    "👌 Completely Relieved Stiffness",
    "⏱️ Full 60-Minute Dedicated Session"
  ],
  "🌿 Aromatherapy Session": [
    "🌿 Pure Lavender & Lemongrass Oils",
    "✨ Soothing Mind-Calming Fragrance",
    "💆 Gentle Rhythmic Flow Strokes",
    "🕊️ Deep Stress & Anxiety Relief",
    "👌 Soft Warm Towel Wraps",
    "🍵 Post-Massage Herbal Green Tea"
  ],
  "🦶 Foot Reflexology": [
    "🦶 Targeted Acupressure Points",
    "🌿 Warm Peppermint Foot Soak",
    "✨ Instant Relief from Sore Feet",
    "👌 Improved Blood Circulation",
    "💆 Relaxing Calf & Heel Rub",
    "🛋️ Plush Reclining Lounger"
  ],
  "🧖 Ayurvedic Potli Massage": [
    "🧖 Heated Herbal Poultice Therapy",
    "🌿 Ancient Medicated Herbs",
    "✨ Relieved Chronic Back & Joint Ache",
    "👌 Deep Heat Penetration",
    "💆 Nourishing Traditional Strokes",
    "👍 Restored Energy & Vitality"
  ],
  "🧴 Body Scrub": [
    "🧴 Gentle Sea Salt & Walnut Exfoliation",
    "✨ Removed Dead Dull Skin",
    "💧 Deep Coconut Butter Hydration",
    "👌 Baby-Soft Smooth Skin Finish",
    "🚿 Warm Rain Shower Facility",
    "🌸 Sweet Natural Body Scent"
  ],
  "💅 Gel Nail Extensions": [
    "💅 Lightweight & Strong Extensions",
    "✨ Flawless Shape & Apex",
    "💎 3+ Weeks Long-Lasting Durability",
    "👌 Zero Natural Nail Damage",
    "🎨 Exact Reference Photo Match",
    "🧼 Autoclaved Sanitized Tools"
  ],
  "✨ Chrome Nail Art": [
    "✨ Ultra Reflective Mirror Finish",
    "🎨 Detailed Freehand French Tips",
    "💎 Secure Rhinestone Placement",
    "💅 Smooth Glossy Gel Topcoat",
    "👌 Trendy Modern Aesthetic",
    "📸 Instagram Ready Nails"
  ],
  "👁️ Lash Extensions": [
    "👁️ Featherlight Weightless Feel",
    "✨ Fluffy Classic / Volume Fan",
    "🌿 Safe Non-Irritating Medical Glue",
    "👌 Seamless Natural Lash Isolation",
    "👁️ Instant Eye-Opening Look",
    "⏱️ 4-Week Great Retention"
  ],
  "🦶 Spa Pedicure": [
    "🦶 Deep Callus & Dead Skin Removal",
    "🌿 Relaxing Bubble Salt Soak",
    "🧴 Hydrating Clay Mask & Scrub",
    "💆 Soothing Calf Foot Massage",
    "💅 Neat Cuticle Polish Finish",
    "🛋️ Relaxing Recliner"
  ],
  "💅 Russian Manicure": [
    "💅 Impeccable Clean Cuticle Pocket",
    "✨ Flawless E-file Precision",
    "👌 Under-Cuticle Gel Polish Application",
    "💎 Super Neat High-End Finish",
    "🌿 Zero Cuticle Bleeding or Pain",
    "💅 Long Lasting Growth Buffer"
  ],
  "👰 HD Bridal Makeup": [
    "✨ 16-Hour Sweatproof Longevity",
    "💄 Flawless Natural Base (Not Cakey)",
    "🎨 Exact Skin Tone Match",
    "👁️ Mesmerizing Eye Makeup & Lashes",
    "💎 Luxury Brands (MAC, Charlotte Tilbury)",
    "📸 Stunning in 4K Wedding Photos",
    "👑 True Princess Makeover"
  ],
  "👗 Saree & Dupatta Draping": [
    "👗 Razor-Sharp Crisp Pleats",
    "🔒 Pin-Drop Secure & Comfortable",
    "✨ Flattering Figure Accentuation",
    "👰 Effortless Bridal Movement",
    "👌 Zero Creasing or Slipping",
    "⏱️ Fast & Patient Draping"
  ],
  "💇 Elegant Hair Updo": [
    "👑 Regal Crown Braids & Bun",
    "🌸 Beautiful Real Floral Placement",
    "🔒 Strong All-Day Hairpin Hold",
    "✨ Flawless Texture & Shine",
    "👌 Complemented Bridal Jewelry",
    "💆 Zero Pulling or Scalp Pain"
  ],
  "✨ Airbrush Makeup": [
    "✨ Ultra-Fine Featherlight Mist Base",
    "🌧️ Completely Waterproof & Tearproof",
    "🎨 HD Camera Ready Finish",
    "👌 Seamless Pores & Texture Blurring",
    "💄 Zero Caking Around Smile Lines",
    "✨ Glowing Radiant Complexion"
  ],
  "🧖 Pre-Bridal Care": [
    "🧖 Full Body Exfoliation & D-Tan",
    "✨ Instant Facial Bridal Glow",
    "💆 Relaxing Stress-Buster Massages",
    "👌 Soft Silky Skin Texture",
    "💅 Pedicure & Manicure Pampering",
    "👰 Ready for the Big Day"
  ],
  "✨ HydraFacial": [
    "✨ 7-Step Vortex Pore Extraction",
    "💧 Deep Hyaluronic Acid Hydration",
    "👌 Gentle Painless Suction",
    "✨ Instant Radiant Plumped Glow",
    "🔬 US-FDA Grade Machine Used",
    "🌿 Zero Redness or Downtime"
  ],
  "🧖 Anti-Tan Cleanup": [
    "🧖 Brightened Sun-Tanned Skin",
    "🧼 Thorough Blackhead & Whitehead Removal",
    "🌿 Cooling Herbal Calming Mask",
    "💆 Gentle Facial Massage",
    "👌 Even-Toned Fresh Look",
    "✨ Visible Clean Complexion"
  ],
  "🌿 Korean Glass Skin Therapy": [
    "🌿 Multi-Layer Moisture Infusion",
    "✨ Luminous Dewy Glass Glow",
    "💧 Replenished Skin Moisture Barrier",
    "👌 Ultra Smooth Skin Texture",
    "🧴 Premium K-Beauty Serums",
    "💎 Youthful Plumped Appearance"
  ],
  "🖤 Charcoal Detox": [
    "🖤 Deep Follicle Impurities Removal",
    "🧼 Excess Sebum & Oil Control",
    "✨ Refined Skin Texture",
    "👌 Tightened Enlarged Pores",
    "🌿 Soothing Green Tea Mask",
    "✨ Clear Mattified Finish"
  ],
  "🧴 Chemical Peel": [
    "🧴 Gentle Glycolic/Lactic Exfoliation",
    "✨ Faded Acne Marks & Pigmentation",
    "👌 Smooth Skin Cell Turnover",
    "👩‍⚕️ Supervised by Skin Expert",
    "📋 Clear Post-Peel Sunscreen Advice",
    "✨ Fresh Rejuvenated Skin Layer"
  ],
  "🌿 Shirodhara": [
    "🌿 Continuous Warm Medicated Oil Flow",
    "✨ Relieved Chronic Insomnia & Stress",
    "🕊️ Deep Meditative State of Mind",
    "👌 Relieved Mental Exhaustion",
    "🪵 Authentic Brass Urli Setup",
    "😊 Very Gentle Vaidya Practitioner"
  ],
  "💆 Abhyanga Full Body Massage": [
    "💆 7-Position Traditional Body Strokes",
    "🌿 Pure Sesame & Dhanwantharam Oil",
    "✨ Relieved Joint Stiffness & Vata",
    "💪 Improved Lymphatic Circulation",
    "🪵 Traditional Wooden Droni Table",
    "🧖 Followed by Herbal Steam"
  ],
  "🌿 Herbal Face Lepam": [
    "🌿 100% Pure Sandal & Turmeric Paste",
    "✨ Natural Skin Radiance & Detox",
    "💧 Soothing Cooling Effect",
    "👌 Tamed Blemishes & Heat Rash",
    "🌿 Free from Chemicals",
    "🍵 Rejuvenating Experience"
  ],
  "🧖 Steam Bath": [
    "🧖 Herbal Medicated Steam Chamber",
    "🌿 Detoxified Pores & Sweat Glands",
    "✨ Relieved Muscular Soreness",
    "👌 Head Kept Cool Naturally",
    "🚿 Clean Shower Area Post-Steam",
    "🕊️ Re-energized Body"
  ],
  "💆 Kati Vasti": [
    "💆 Warm Medicated Oil Pool on Lower Back",
    "✨ Relieved Chronic Lumbar Pain",
    "🌿 Deep Disc & Muscle Nourishment",
    "👌 Relaxed Stiff Spinal Tissues",
    "🪵 Expert Herbal Dough Boundary",
    "👍 Visible Pain Relief"
  ],
  "💨 Express Blowdry & Curls": [
    "💨 Bouncy Long-Lasting Volume",
    "✨ Smooth Glossy Hair Finish",
    "🔥 Safe Thermal Protection Spray",
    "👌 Gorgeous Soft Curls",
    "⚡ Fast 30-Minute Turnaround",
    "💃 Party Ready Look"
  ],
  "🧴 Deep Conditioning Spa": [
    "🧴 Intense Argan Moisture Mask",
    "✨ Tamed Dry Damaged Strands",
    "💆 Relaxing Steam Penetration",
    "👌 Silky Feather-Soft Touch",
    "🌿 Healthy Shine Restored",
    "💨 Beautifully Blown Dry"
  ],
  "✨ Beach Waves Styling": [
    "✨ Effortless Textured Tousled Waves",
    "👌 Non-Sticky Flexible Hold",
    "🎨 Trendy Modern Silhouette",
    "💨 Long-Lasting Shape All Night",
    "👌 Complemented Party Outfit",
    "📸 Great Photo Appeal"
  ],
  "💆 Relaxing Scalp Wash": [
    "💆 Invigorating Scalp Acupressure",
    "🌿 Refreshing Mint Shampoo",
    "🚿 Perfect Water Temperature",
    "✨ Cleansed Product Buildup",
    "🧼 Clean Reclining Basin",
    "👌 Deeply Relaxing"
  ],
  "✂️ Split-Ends Trim": [
    "✂️ Precision Micro-Trimming",
    "👌 Kept Full Hair Length Intact",
    "🌿 Eliminated Frizzy Damaged Ends",
    "✨ Neat Healthy Hairline",
    "👌 Quick & Highly Accurate",
    "💇 Fresh Polished Look"
  ],
  "👶 Toddler First Haircut": [
    "🚗 Fun Toy Car Salon Chair",
    "📺 Favorite Cartoons on Screen",
    "✂️ Super Gentle Patient Barber",
    "⚡ Tear-Free & Quick Snips",
    "🎁 First Haircut Certificate & Hair Keepsake",
    "🎈 Free Balloon & Smile"
  ],
  "🧒 Fun Boy/Girl Styling": [
    "✂️ Smart Trendy School Haircut",
    "👌 Quick & Clean Lineup",
    "✨ Cool Spike / Braid Detailing",
    "😊 Stylist Kept Kid Engaged",
    "🧼 Sanitized Child-Friendly Scissors",
    "👍 Very Neat Finish"
  ],
  "🎀 Kids Braids & Beads": [
    "🎀 Colorful Fun Hair Beads",
    "✨ Gentle Scalp-Safe Braiding",
    "👌 Cute Princess Style",
    "🔒 Long-Lasting Neat Hold",
    "😊 Very Patient Stylist",
    "📸 Adorable Kids Look"
  ],
  "✂️ Gentle Trimming": [
    "✂️ Fast 10-Minute Snip Session",
    "🧼 Clean Disposable Cape",
    "👌 Rounded Safety Scissors Used",
    "😊 Friendly Playful Staff",
    "✨ No Hair Prickling on Clothes",
    "👍 Stress-Free for Parents"
  ],
  "🧴 Mild Bubble Wash": [
    "🧴 Tear-Free Gentle Baby Shampoo",
    "🫧 Fun Bubble Foam Play",
    "🚿 Gentle Warm Water Spray",
    "🧼 Clean Recliner Station",
    "👌 Fresh Clean Scent",
    "😊 Happy Tearless Kid"
  ],
  "✂️ Haircut & Wash": [
    "✂️ Clean Symmetrical Haircut",
    "🚿 Refreshing Warm Hair Wash",
    "💨 Quick Blowdry & Style",
    "😊 Attentive Family Stylist",
    "⏱️ Zero Unnecessary Delay",
    "💰 Great Family Value"
  ],
  "🧵 Painless Threading & Waxing": [
    "🧵 Fast Gentle Threading Technique",
    "🍯 Warm Peel-Off Wax for Arms/Legs",
    "✨ Perfectly Shaped Eyebrow Arch",
    "🌿 Soothing Aloe Vera Gel Post-Care",
    "👌 Minimal Pain & Zero Cuts",
    "🧼 Clean Sterile Strips"
  ],
  "🧴 D-Tan Facial": [
    "🧴 Effective Sun Tan Removal Pack",
    "✨ Instant Facial Radiance",
    "💆 Relaxing Face & Neck Massage",
    "🧼 Deep Cleaned Pores",
    "👌 Visible Freshness",
    "💰 Pocket-Friendly Price"
  ],
  "🧔 Beard Trim": [
    "🧔 Sharp Clean Beard Edges",
    "✂️ Even Mustache & Beard Trimming",
    "🧴 Soothing Aftershave Lotion",
    "👌 Quick & Crisp Look",
    "🧼 Fresh Blade Used",
    "👍 Smart Professional Finish"
  ],
  "🧖 Express Clean Up": [
    "🧖 Quick 20-Min Pore Cleanse",
    "🧼 Gentle Scrub Exfoliation",
    "✨ Instant Dirt & Oil Clear",
    "🌿 Cooling Cucumber Pack",
    "👌 Fresh Glowing Look",
    "⚡ Perfect Lunchtime Grooming"
  ],
  "🦷 Teeth Cleaning & Polishing": [
    "🦷 Ultrasonic Plaque & Tartar Removal",
    "✨ Sparkling Clean Stains Gone",
    "🌿 Gentle Hand & Zero Gum Bleeding",
    "😁 Smooth Polished Enamel",
    "🧼 Autoclaved Sterile Instruments",
    "💡 Helpful Flossing Advice"
  ],
  "✨ Teeth Whitening": [
    "✨ Visible 3-4 Shades Brighter",
    "🔬 Safe Enamel Bleaching Gel",
    "🛡️ Zero Tooth Sensitivity Post-Treatment",
    "😁 Stunning Confident Smile",
    "👌 Fast In-Clinic Session",
    "📸 Instant Noticeable Difference"
  ],
  "🦷 Painless Root Canal (RCT)": [
    "✨ 100% Pain-Free Rotary RCT",
    "👨‍⚕️ Highly Skilled Endodontist",
    "🔬 Precision Digital X-Ray Guided",
    "👑 Flawless Zirconia Crown Fitting",
    "🌿 Effective Local Numbing",
    "⏱️ Completed in Single/Two Sittings"
  ],
  "😁 Dental Aligners / Braces": [
    "😁 Invisible Clear Aligner Trays",
    "🖥️ 3D Digital Smile Simulation",
    "👌 Comfortable Daily Wear",
    "📅 Regular Progress Tracking",
    "💡 Transparent EMI Pricing",
    "🦷 Flawless Teeth Alignment"
  ],
  "🦷 Tooth Filling": [
    "🦷 Tooth-Colored Composite Resin",
    "✨ Seamless Natural Tooth Match",
    "👌 Strong Bite & Chewing Comfort",
    "🧼 Clean Cavity Excavation",
    "🛡️ Long-Lasting Durability",
    "👨‍⚕️ Quick & Gentle Doctor"
  ],
  "💉 Routine Child Vaccination": [
    "💉 Super Gentle Painless Technique",
    "👶 Doctor Calmed the Baby Warmly",
    "❄️ Strict Vaccine Cold Chain Maintained",
    "📋 Clear Immunization Record Card",
    "🎁 Free Toy & Distraction Used",
    "🩹 Pain-Relief Guidance Given"
  ],
  "🩺 Growth & Milestones Checkup": [
    "🩺 In-Depth Height & Weight Tracking",
    "💡 Clear Developmental Guidance",
    "👂 Doctor Listened to All Queries",
    "🎯 Reassuring Pediatric Care",
    "👶 Friendly Interactive Checkup",
    "📋 Comprehensive Growth Chart"
  ],
  "🤒 Fever & Allergy Consult": [
    "🎯 Accurate Root-Cause Diagnosis",
    "💊 Minimal Rational Medications",
    "🌡️ Quick Recovery in 24-48 Hours",
    "👨‍⚕️ Highly Experienced Pediatrician",
    "📱 Responsive Follow-up Support",
    "👍 Peace of Mind for Parents"
  ],
  "🥛 Infant Nutrition Advice": [
    "🥛 Practical Weaning & Feeding Chart",
    "🥦 Healthy Weight Gain Guidance",
    "💡 Addressed Picky Eating Patiently",
    "🌿 Wholesome Natural Diet Tips",
    "👶 Baby-Friendly Milestones",
    "😊 Warm & Encouraging Doctor"
  ],
  "👁️ Computer Vision Eye Test": [
    "🎯 Precise Digital Power Testing",
    "🔬 Advanced Autorefractor Machine",
    "💡 Zero Eye Strain Guarantee",
    "👁️ Thorough Retina & Pressure Check",
    "👨‍⚕️ Patient Detailed Optometry",
    "🧼 Sanitized Chin Rest & Tools"
  ],
  "👓 Prescription Eyeglasses": [
    "👓 Blue-Cut Anti-Glare Coating",
    "☁️ Ultra-Lightweight Titanium Frame",
    "👌 Custom Nose Bridge Adjustment",
    "✨ Crystal Clear Sharp Vision",
    "⚡ Fast Same-Day Lens Fitting",
    "🎁 Hard Case & Microfiber Kit"
  ],
  "👁️ Contact Lens Trial": [
    "👁️ Breathable High-Oxygen Lenses",
    "💧 Daily Hydration & Comfort",
    "💡 Patient Demonstration on Insertion",
    "👌 Zero Dryness or Irritation",
    "🧴 Lens Solution Included",
    "🎯 Perfect Power Fit"
  ],
  "🔍 Retina & Cataract Check": [
    "🔬 High-Resolution Fundus Imaging",
    "👁️ Comprehensive Slit-Lamp Exam",
    "👨‍⚕️ Experienced Eye Surgeon Advice",
    "💡 Clear Explanation of Scan Reports",
    "🛡️ Safe Non-Invasive Diagnostics",
    "👍 Highly Ethical Practice"
  ],
  "🦵 Knee & Joint Physio": [
    "🦵 Restored Joint Range of Motion",
    "⚡ Advanced IFT & Ultrasound Therapy",
    "✨ Significant Pain Reduction",
    "🏋️ Targeted Quadriceps Strengthening",
    "👨‍⚕️ Hands-On Mobilization Technique",
    "💪 Confident Pain-Free Walking"
  ],
  "🧍 Back & Spine Rehab": [
    "🧍 Sciatica & Disc Pain Relief",
    "🎯 Posture Realignment Exercises",
    "🔬 Spinal Decompression & Traction",
    "💡 Ergonomic Work-Desk Guidance",
    "💪 Core Strengthening Regimen",
    "✨ Long-Lasting Spine Comfort"
  ],
  "🏃 Sports Injury Recovery": [
    "🏃 Fast Return-to-Sport Program",
    "⚡ Muscle Spasm & Tendon Healing",
    "🔬 Kinesiology Taping Applied",
    "💪 Agility & Functional Training",
    "👨‍⚕️ Sports Physio Specialist",
    "👍 Regained Peak Performance"
  ],
  "⚡ Post-Surgery Mobility Care": [
    "⚡ Gradual Safe Joint Mobilization",
    "🦵 Reduced Post-Operative Swelling",
    "💪 Restored Independence & Strength",
    "📋 Milestone-Based Recovery Plan",
    "😊 Extremely Patient Physiotherapist",
    "🏠 Practical Home Exercise Regimen"
  ],
  "💆 Cupping & Dry Needling": [
    "💆 Released Deep Muscle Trigger Points",
    "✨ Immediate Fascial Pain Release",
    "🔬 Sterile Disposable Needles Used",
    "💪 Relieved Neck & Shoulder Tightness",
    "👌 Performed by Certified Specialist",
    "🕊️ Deep Muscular Relaxation"
  ],
  "🩸 Full Body Health Check": [
    "🩸 80+ Comprehensive Health Parameters",
    "🔬 NABL Certified Automated Testing",
    "📱 Same-Day WhatsApp & Email PDF",
    "💡 Free Doctor Report Consultation",
    "💰 Highly Discounted Package",
    "🧼 Sterile Vacutainer Tubes Used"
  ],
  "🧪 HbA1c Sugar Test": [
    "🧪 Accurate 3-Month Blood Glucose Metric",
    "⚡ Fast 4-Hour Digital Report",
    "💉 Painless Single-Prick Collection",
    "🔬 Fully Automated Chemistry Analyzer",
    "📋 Easy-to-Read Graph Format",
    "👍 Highly Reliable Values"
  ],
  "🧬 Thyroid & Lipid Profile": [
    "🧬 Ultra-Sensitive Immunoassay Testing",
    "❤️ Cholesterol & Triglyceride Breakdown",
    "📱 Fast Turnaround Time",
    "🧤 Disposable Gloves & Vacutainers",
    "🎯 Accurate Diagnostic Markers",
    "👨‍⚕️ Trusted by Leading Doctors"
  ],
  "🔬 CBC Blood Count": [
    "🔬 Complete Platelet & Hemoglobin Screen",
    "⚡ Express 2-Hour Report Generation",
    "💉 Gentle Vein Draw by Expert Tech",
    "🎯 High Precision Cell Counter",
    "📋 Color-Coded Normal Range Flags",
    "🧼 100% Sterile Needle Disposal"
  ],
  "🩻 Digital X-Ray / ECG": [
    "🩻 Crystal-Clear Digital Radiography",
    "❤️ Instant 12-Lead Computerized ECG",
    "⚡ Fast In-Clinic Imaging",
    "👨‍⚕️ Signed by Senior Radiologist/Cardiologist",
    "🧼 Sanitized Imaging Table",
    "⏱️ Zero Waiting Delay"
  ],
  "🧴 Acne & Scar Laser Treatment": [
    "🔬 Fractional CO2 Laser Technology",
    "✨ Visible Acne Scar Smoothing",
    "🌿 Reduced Active Breakouts & Sebum",
    "👨‍⚕️ MD Dermatologist Supervised",
    "🛡️ Safe Cooling System Used",
    "📋 Clear Post-Procedure Healing Kit"
  ],
  "💉 PRP Hair Therapy": [
    "💉 High-Concentration Platelet Injection",
    "🌿 Promoted New Hair Follicle Growth",
    "🛡️ Reduced Hair Fall Significantly",
    "👌 Performed with Derma-Numbing Spray",
    "🔬 Sterile Closed-System Centrifuge",
    "💪 Stronger Hair Density"
  ],
  "✨ Laser Hair Reduction": [
    "✨ US-FDA Triple Wavelength Diode Laser",
    "❄️ Painless Ice-Cooling Contact Tip",
    "👌 Noticeable Hair Thinning in 2 Sessions",
    "🧼 Thorough & Gentle Laser Aesthetician",
    "🔒 100% Private Clean Treatment Room",
    "💰 Affordable Multi-Session Packages"
  ],
  "🌿 Pigmentation Treatment": [
    "✨ Faded Melasma & Dark Spots",
    "🔬 Q-Switched Nd:YAG Laser",
    "💧 Restored Even Luminous Skin Tone",
    "🌿 Gentle Non-Ablative Glow",
    "📋 Custom Sunscreen & Skincare Plan",
    "👌 Visible Complexion Clarity"
  ],
  "🩺 Skin Allergy Consult": [
    "🎯 Accurate Root Cause Allergy Identification",
    "💊 Minimal Targeted Medications",
    "✨ Fast Relief from Itching & Rash",
    "👂 Patient In-Depth Consultation",
    "💡 Practical Lifestyle & Skincare Tips",
    "👍 Compassionate Dermatologist"
  ],
  "🦴 Joint Pain Consultation": [
    "🎯 Accurate Joint Assessment",
    "💡 Clear X-Ray & MRI Review",
    "🌿 Conservative Non-Surgical Preference",
    "👨‍⚕️ Renowned Senior Orthopedic Surgeon",
    "✨ Effective Pain Management",
    "👂 Patient Listening to Symptoms"
  ],
  "🦵 Arthritis Therapy": [
    "🦵 Lubricating Joint Injections / Gel",
    "✨ Restored Knee Bending & Walking",
    "💪 Tailored Muscle Strengthening Guide",
    "🌿 Reduced Morning Joint Stiffness",
    "💡 Weight Management & Diet Tips",
    "👍 Greatly Improved Quality of Life"
  ],
  "🩹 Fracture & Cast Treatment": [
    "🩹 Lightweight Waterproof Cast Application",
    "🎯 Perfect Bone Alignment & Setting",
    "🩻 Regular Follow-up X-Ray Monitoring",
    "👌 Smooth Itch-Free Cast Removal",
    "💪 Complete Bone Healing",
    "👨‍⚕️ Reassuring & Caring Treatment"
  ],
  "🧍 Cervical & Spine Consult": [
    "🧍 Targeted Neck & Lower Back Diagnosis",
    "✨ Relieved Nerve Compression & Tingling",
    "💡 Ergonomic Posture & Pillow Advice",
    "💪 Core & Spine Physical Therapy Plan",
    "🌿 Minimized Painkillers Safely",
    "👍 Restored Spine Flexibility"
  ],
  "🦴 Bone Mineral Density (BMD)": [
    "🔬 Accurate DEXA Bone Scanner",
    "🦴 Osteoporosis Risk Evaluation",
    "💊 Tailored Calcium & Vitamin D3 Therapy",
    "📋 Clear Colored Density Report",
    "💡 Fall Prevention Guidance",
    "⚡ Fast & Painless Scan"
  ],
  "🩺 General Health Check": [
    "🩺 In-Depth Whole-Body Examination",
    "👂 Doctor Listened Patiently to All Concerns",
    "🎯 Accurate Diagnosis & Rational Rx",
    "💡 Actionable Diet & Sleep Guidance",
    "😊 Friendly & Reassuring Demeanor",
    "🧼 Clean Well-Maintained Clinic"
  ],
  "❤️ Blood Pressure Management": [
    "❤️ Precise Digital & Manual BP Check",
    "💊 Tailored Minimal Antihypertensive Dose",
    "🥗 Low-Sodium Heart-Healthy Diet Plan",
    "📱 Routine Home Monitoring Protocol",
    "✨ Stabilized Blood Pressure Readings",
    "👍 Trustworthy Family Physician"
  ],
  "🩸 Diabetes Care": [
    "🩸 Routine Sugar & HbA1c Evaluation",
    "🎯 Personalized Glycemic Target Plan",
    "🦶 Diabetic Foot & Nerve Check",
    "💡 Sustainable Low-Carb Meal Advice",
    "✨ Steady Controlled Blood Sugars",
    "👨‍⚕️ Empathetic Long-Term Care"
  ],
  "🤒 Seasonal Infection Treatment": [
    "🤒 Prompt Viral & Flu Diagnosis",
    "💊 Fast-Acting Relief Medications",
    "🌡️ Fever Normalized in 24-48 Hours",
    "🍵 Hydration & Recovery Guidance",
    "👍 Prevented Unnecessary Antibiotics",
    "📱 Easy Follow-up Access"
  ],
  "📋 Medical Certificate": [
    "📋 Thorough Fitness Evaluation",
    "⚡ Prompt Verifiable Documentation",
    "🩺 Pulse, BP & Vision Testing",
    "📄 Official Signed Stamp Certificate",
    "😊 Quick & Hassle-Free Process",
    "💰 Transparent Nominal Fee"
  ],
  "🌿 Chronic Skin Treatment": [
    "🌿 Root-Cause Constitutional Treatment",
    "✨ Healed Eczema & Psoriasis Naturally",
    "🛡️ 100% Steroid-Free Gentle Remedies",
    "👌 Zero Recurrence of Itch & Flare-ups",
    "👨‍⚕️ In-Depth Case Taking Session",
    "💧 Restored Healthy Glowing Skin"
  ],
  "🤕 Migraine & Headache Care": [
    "✨ Significant Reduction in Migraine Attacks",
    "🌿 Safe Natural Potentized Drops",
    "💡 Trigger Identification & Management",
    "🕊️ Relieved Throbbing Pain & Nausea",
    "👌 Non-Drowsy Daytime Formulation",
    "👍 Permanent Long-Term Relief"
  ],
  "🛡️ Immunity Booster Therapy": [
    "🛡️ Strengthened Natural Body Defense",
    "👶 Safe for Young Kids & Elders",
    "🌿 Zero Chemical Additives",
    "✨ Reduced Recurrent Cold & Cough",
    "🍬 Sweet Non-Bitter Sugar Globules",
    "💪 Improved Vitality & Stamina"
  ],
  "🫁 Asthma & Allergy Care": [
    "🫁 Relieved Bronchial Wheezing & Congestion",
    "🌿 Desensitized Seasonal Allergen Triggers",
    "✨ Reduced Dependency on Inhalers",
    "👌 Gentle Root-Level Healing",
    "👂 Compassionate Doctor Consultation",
    "🕊️ Restful Breath & Sleep"
  ],
  "🧘 Stress Management": [
    "🧘 Calmed Mind & Nervous Exhaustion",
    "✨ Restored Natural Deep Sleep Cycles",
    "🌿 Zero Habit-Forming Side Effects",
    "💡 Empathetic Counseling Support",
    "🕊️ Peaceful Rebalanced Energy",
    "👍 Genuine Holistic Care"
  ],
  "👂 Painless Ear Wax Cleaning": [
    "👂 Gentle Micro-Suction Technology",
    "✨ Instant Clear Hearing Restored",
    "🖥️ Live Video Otoscope Camera View",
    "👌 Zero Pain & Zero Water Syringing",
    "🧼 100% Sterile Disposable Tips",
    "👨‍⚕️ Performed by Senior ENT Surgeon"
  ],
  "🎧 Digital Hearing Test (Audiometry)": [
    "🔇 Modern Soundproof Audiometry Booth",
    "📊 Precise Pure Tone & Speech Testing",
    "🎯 Accurate Decibel Hearing Thresholds",
    "💡 Clear Explanation of Audiogram",
    "😊 Patient Experienced Audiologist",
    "⏱️ Fast Same-Day Test Report"
  ],
  "👃 Sinus & Nasal Checkup": [
    "👃 Diagnostic Nasal Endoscopy (DNE)",
    "✨ Relieved Chronic Sinus Congestion",
    "🌿 Gentle Saline Rinse & Spray Regimen",
    "💡 Clear Visualization of Nasal Polyps",
    "👌 Avoided Unnecessary Surgery",
    "👍 Restored Easy Breathing"
  ],
  "🗣️ Throat Infection Consult": [
    "🗣️ Detailed Laryngeal Examination",
    "✨ Fast Relief from Sore Throat & Hoarseness",
    "🎯 Targeted Non-Antibiotic Therapy",
    "💡 Vocal Cord Care Guidelines",
    "👂 Doctor Listened to All Symptoms",
    "👌 Quick Swallowing Relief"
  ],
  "🦻 Hearing Aid Trial": [
    "🦻 Invisible Discreet Digital Hearing Aids",
    "🎯 Custom Noise-Reduction Programming",
    "📱 Bluetooth Phone Call & TV Streaming",
    "🎧 Free Live In-Clinic Trial Demo",
    "💡 Transparent Multi-Brand Pricing",
    "📜 Warranty & Free Lifetime Tuning"
  ],
  "✨ 9H Ceramic Coating": [
    "🪞 Deep Mirror Glass Gloss",
    "💧 Insane Hydrophobic Water Beading",
    "🛡️ 9H Hardness Scratch Resistance",
    "☀️ Complete UV & Oxidation Shield",
    "📜 Official Digital Warranty Card",
    "💡 Cured Under Infrared Lamps",
    "🚗 Showroom Shine Restored"
  ],
  "🪞 3-Stage Paint Correction": [
    "✨ Swirl Marks & Micro-Scratches Gone",
    "🪞 High-Gloss Clear Coat Reflection",
    "🔬 Precision Dual-Action Polisher Work",
    "👌 No Holograms or Buffer Trails",
    "🎨 Enhanced Rich Deep Paint Hue",
    "👨‍🔧 Master Detailer Craftsmanship"
  ],
  "🧼 Deep Interior Detailing": [
    "🧼 Steam Cleaned Upholstery & Carpets",
    "🌸 Eliminated Deep Odors & Bacteria",
    "🛋️ Leather Conditioned & Matte Finished",
    "🧹 Dust-Free AC Vents & Consoles",
    "👌 Factory Fresh Interior Look",
    "✨ Spotless Stain Removal"
  ],
  "🔧 Engine Bay Cleaning": [
    "🔧 Safe Steam Cleaning & Degreasing",
    "✨ Dressing of Rubber Hoses & Plastics",
    "🛡️ Electrical Sensors Safely Masked",
    "👌 Factory Clean Engine Finish",
    "👨‍🔧 Performed by Trained Specialists",
    "👍 Showroom Clean Bay"
  ],
  "🪟 Windshield Water Repellent": [
    "🪟 Rain-Repellent Nano Coating",
    "🌧️ High Water Fly-Off at Speed",
    "✨ Streak-Free Night Driving Clarity",
    "🛡️ Wiper Judder-Free Application",
    "👌 Crystal-Clear Windshield View",
    "⚡ Improved Monsoon Safety"
  ],
  "🛡️ Full Body TPU PPF": [
    "🛡️ Self-Healing Scratch Resistance",
    "👌 Seamless Invisible Edge Wrapping",
    "🪞 Instant High-Gloss Paint Depth",
    "🛡️ Maximum Stone Chip & Key Protection",
    "📜 5 to 10-Year Brand Warranty",
    "🔬 Installed in Dust-Free Bay",
    "🚗 Ultimate Paint Armour"
  ],
  "🚗 Front Bumper & Hood PPF": [
    "🛡️ High-Impact Zone Stone Chip Shield",
    "👌 Precision Pre-Cut CNC Plotter Fit",
    "✨ Zero Blade Knifing on Car Body",
    "💧 Hydrophobic Topcoat Included",
    "🪞 Flawless Gloss Match with Rest of Car",
    "👍 Cost-Effective Protection"
  ],
  "🪞 Piano Black Roof Wrap": [
    "🪞 Ultra-Glossy Panoramic Glass Look",
    "✨ Bubble-Free Cast Vinyl Film",
    "☀️ High Heat & UV Resistance",
    "👌 Flawless Razor-Sharp Edge Tuck",
    "🚗 Sporty Dual-Tone Aesthetic",
    "🛡️ Leaves No Glue Residue on Removal"
  ],
  "💡 Sunroof TPU Protection": [
    "💡 100% UV & Infrared Heat Rejection",
    "🛡️ Shatter-Proof Stone Protection",
    "✨ Crystal Clear Transparency",
    "❄️ Noticeable Cabin Temperature Drop",
    "👌 Durable Outdoor Longevity",
    "👍 Safe Glass Tinting"
  ],
  "✨ Headlight Tint Film": [
    "✨ Smoked Gloss / Clear TPU Layer",
    "🛡️ Protected Lenses from Yellowing & Chips",
    "💡 Zero Drop in Headlamp Lux Output",
    "👌 Self-Healing Rock Chip Guard",
    "🚗 Aggressive Sporty Front Look",
    "🌧️ Weatherproof Sealing"
  ],
  "🚿 High-Pressure Snow Foam Wash": [
    "🚿 Thick pH-Neutral Snow Foam",
    "🧼 2-Bucket Scratch-Free Wash Method",
    "✨ Spotless Streak-Free Drying",
    "🧽 Clean Soft Microfiber Towels Used",
    "🚗 Rinsed Road Grime from Crevices",
    "👌 Gleaming Clean Finish"
  ],
  "🚗 Underbody Rust Cleaning": [
    "🚗 High-Pressure Hydraulic Under-Wash",
    "🧼 Cleared Mud & Road Salt Buildup",
    "🛡️ Prevented Chassis Rust Formation",
    "👌 Thorough Wheel-Arch Flushing",
    "👨‍🔧 Inspected Underbody Components",
    "👍 Essential Post-Rain Maintenance"
  ],
  "🧹 Deep Interior Vacuum": [
    "🧹 Powerful Multi-Point Vacuuming",
    "🛋️ Clean Under-Seat Dust Removal",
    "🦶 Thorough Floor Mat Scrub & Drying",
    "🧹 Boot & Trunk Cleaned Spick & Span",
    "👌 Zero Sand or Pet Hair Left Behind",
    "✨ Neat Tidy Cabin"
  ],
  "✨ Dashboard & Trim Polish": [
    "✨ Matte Non-Greasy UV Dashboard Polish",
    "🌸 Fresh Cabin Fragrance Spray",
    "🚪 Cleaned Door Panels & Cupholders",
    "🪟 Streak-Free Inside Glass Wipe",
    "👌 Repels Dust Buildup",
    "👍 Premium Cabin Feel"
  ],
  "🛞 Tire Shine Dressing": [
    "🛞 Deep Glossy Black Tire Dressing",
    "✨ Cleaned Brake Dust from Alloy Rims",
    "👌 Sling-Free Long-Lasting Shine",
    "🛡️ Protects Rubber from Sidewall Cracking",
    "🚗 Showroom Stance Look",
    "👍 High-End Look"
  ],
  "🛢️ Synthetic Engine Oil Change": [
    "🛢️ 100% Genuine Fully-Synthetic Oil",
    "🔧 Brand New OEM Oil & Air Filter",
    "🚀 Butter Smooth Engine Revving",
    "⛽ Improved Fuel Economy",
    "💡 Transparent Unboxing of Oil Cans",
    "⏱️ Quick 45-Min Lube Service"
  ],
  "🛑 Brake Pad Replacement": [
    "🛑 Crisp & Confident Braking Response",
    "💯 Genuine OEM Ceramic Brake Pads",
    "🔧 Caliper Greasing & Rotor Skimming Done",
    "🤫 Zero Squealing or Grinding Noise",
    "🛡️ Thorough Brake Fluid Bleed",
    "👍 Total Road Safety"
  ],
  "❄️ AC Filter Cleaning": [
    "❄️ High-Flow Cabin Filter Cleaning",
    "🌸 Eliminated Mildew & Cabin Odor",
    "🌬️ Increased Blower Airflow",
    "❄️ Rapid Cabin Chilling",
    "👌 Clean Dust-Free Fresh Air",
    "👍 Inexpensive Comfort Upgrade"
  ],
  "🔍 40-Point Safety Checkup": [
    "🔍 Comprehensive Digital Health Scan",
    "🔋 Battery, Coolant & Fluid Top-Up",
    "📋 Detailed Color-Coded Inspection Sheet",
    "💡 Video Proof Shared on WhatsApp",
    "🚫 Zero Pushy Upselling",
    "👨‍🔧 Highly Competent Mechanics"
  ],
  "🚗 Suspension Overhaul": [
    "🚗 Eliminated Rattling & Thumping Sounds",
    "🛣️ Smooth Bump Absorption Restored",
    "🔧 Genuine Bushings & Strut Replacement",
    "👌 Tight Steering Feedback",
    "⚖️ Included Alignment Check",
    "👍 Smooth Highway Cruising"
  ],
  "❄️ AC Gas Refill & Top-Up": [
    "❄️ Ice-Cold Cabin Chilling in 2 Mins",
    "🔬 100% Pure R134a/R1234yf Refrigerant",
    "🛢️ Added Compressor Lubricant Oil",
    "⚡ Tested under Digital Pressure Gauges",
    "👌 Chills Even in Scorching 45°C Heat",
    "👍 Fast 30-Minute Refill"
  ],
  "🧼 Cooling Coil Deep Clean": [
    "🧼 Eliminated Mold & Musty AC Odors",
    "🌬️ Restored Maximum Vent Blower Throw",
    "🌿 Disinfected Evaporator with Foam Spray",
    "👌 Cleaned Without Dashboard Removal",
    "🌸 Fresh Crisp Cabin Air",
    "❄️ Maximum Cooling Efficiency"
  ],
  "🔧 AC Compressor Repair": [
    "🔧 Solved Clutch & Valve Noise",
    "🤫 Super Silent AC Operation",
    "💯 Genuine OEM Replacement Parts",
    "⚡ Consistent Cooling in Traffic Jams",
    "📜 Service Warranty Included",
    "👨‍🔧 Master AC Technician"
  ],
  "🌬️ Cabin Air Filter Change": [
    "🌬️ High-Efficiency PM2.5 Activated Carbon Filter",
    "🌸 Trapped Dust, Pollen & Exhaust Smells",
    "❄️ Smooth Airflow Through All Vents",
    "👌 Easy Quick Replacement",
    "👍 Essential for Clean Breathing",
    "💰 Very Nominal Cost"
  ],
  "🔬 Nitrogen Leak Test": [
    "🔬 Pinpointed Micro-Leak in AC Piping",
    "🎯 Solved Persistent Gas Loss Issue",
    "🛡️ High-Pressure Nitrogen Verification",
    "💡 Repaired O-Rings & Condenser",
    "👌 Guaranteed Leak-Free Seal",
    "👍 Saved Future Refill Costs"
  ],
  "📐 3D Laser Wheel Alignment": [
    "📐 High-Precision 3D Camera Sensors",
    "🚗 Straight-Line Driving with Zero Pulling",
    "🎯 Perfectly Centered Steering Wheel",
    "🛞 Maximum Tire Life & Even Wear",
    "📋 Printed Before/After Angle Report",
    "⚡ Fast 15-Minute Calibration"
  ],
  "⚖️ Dynamic Wheel Balancing": [
    "⚖️ High-Speed Vibration 100% Eliminated",
    "🎯 Precision Clip-On / Stick-On Weights",
    "🛣️ Smooth Cruising at 120 km/h",
    "🔬 Italian Digital Balancing Machine",
    "👌 Smooth Steering Wheel Feel",
    "👍 Safer Highway Drives"
  ],
  "💨 Nitrogen Air Refill": [
    "💨 Maintained Stable Tire Pressure",
    "❄️ Cooler Running Tires on Long Drives",
    "⛽ Improved Fuel Mileage",
    "🛡️ Reduced Pressure Loss Over Weeks",
    "👌 Extended Tire Rubber Life",
    "⚡ Fast Automated Nitrogen Inflator"
  ],
  "🛞 New Tire Replacement": [
    "🛞 Fresh Recent Manufacturing DOT Code",
    "💯 Top Brand Certified Tires (Michelin, Bridgestone)",
    "🔧 Scratch-Free Automatic Rim Mounter Used",
    "💰 Unbeatable Competitive Rates",
    "📜 Official Manufacturer Warranty Registered",
    "🎁 Free Alignment Included"
  ],
  "🔧 Rim Bend Repair": [
    "🔧 Hydraulic Cold Bend Correction",
    "👌 100% True Round Rim Restored",
    "💨 Solved Air Leakage Along Bead",
    "🛡️ Zero Damage to Alloy Paint",
    "⚖️ Checked with Dial Gauge Indicator",
    "👍 Cost-Effective Alternative to New Rim"
  ],
  "🚗 Bumper Scratch Removal": [
    "🎨 100% Computerized Color Match",
    "✨ Blended Seamlessly into Original Paint",
    "👌 No Paint Edge Lines Visible",
    "⚡ Quick Same-Day Express Touchup",
    "🛡️ High-Gloss Scratch-Resistant Clear Coat",
    "💰 Cost-Effective Bumper Repair"
  ],
  "🔨 Panel Dent Pulling": [
    "🔨 Paintless Dent Repair (PDR) Technique",
    "👌 Original Factory Paint Preserved",
    "🎯 Flawless Body Line Alignment",
    "🚗 Restored Factory Panel Contours",
    "👨‍🔧 Master Denter Craftsmanship",
    "👍 Invisible Repair"
  ],
  "🎨 Full Body Overcoat Painting": [
    "🏢 Baked in Heated Dust-Free Paint Booth",
    "🎨 High-End Dupont/PPG Polyurethane Paint",
    "✨ Deep Mirror Gloss Finish",
    "📜 Multi-Year Paint Peeling Warranty",
    "👌 Flawless Orange-Peel Texture Match",
    "🚗 Looked Brand New from Factory"
  ],
  "✨ Rubbing & Polish": [
    "✨ Removed Paint Oxidation & Scuffs",
    "🪞 Restored Vibrant Deep Paint Gloss",
    "🔬 3M Rubbing Compound & Foam Pads",
    "👌 Silky Smooth Surface Feel",
    "🛡️ Finished with Liquid Wax Coat",
    "👍 Great Value Revitalization"
  ],
  "🛡️ Anti-Rust Undercoating": [
    "🛡️ Heavy-Duty Rubberized Bitumen Coating",
    "🚗 100% Rust & Corrosion Protection",
    "🔇 Dampened Road & Gravel Noise",
    "📜 5-Year Underbody Warranty",
    "👌 Covered Silencer & Wheel Wells",
    "👍 Essential for Coastal & Monsoon Driving"
  ],
  "📱 Android Touchscreen Headunit": [
    "⚡ Lightning Fast 8-Core Processor",
    "📱 Wireless Apple CarPlay & Android Auto",
    "🖥️ Crisp QLED High-Definition Display",
    "🔌 100% Coupler-to-Coupler Safe Wiring",
    "👌 Flush Factory Dashboard Fit Frame",
    "🛡️ Car Warranty Completely Intact"
  ],
  "🔊 Component Speakers & Tweeters": [
    "🎤 Crystal-Clear Vocals & Crisp Highs",
    "🎵 Punchy Mid-Bass Performance",
    "🛡️ Door Damping Sheets Installed",
    "🔌 OEM Harness Adapters Used",
    "👌 Tuned by Audio Specialist",
    "🎧 Concert-Like Music Experience"
  ],
  "🎵 Powered Underseat Subwoofer": [
    "🎵 Deep Rich Punchy Low-End Bass",
    "🚗 Compact Space-Saving Underseat Fit",
    "🎛️ Convenient Wired Remote Bass Controller",
    "⚡ Solid Aluminum Die-Cast Housing",
    "👌 Complemented Factory Speakers",
    "👍 Rich Full-Bodied Sound"
  ],
  "📹 360° HD Parking Camera": [
    "📹 Crisp 1080p Night-Vision Clarity",
    "🚗 Dynamic Trajectory Steering Guidelines",
    "🛡️ Blind-Spot View on Indicator Turn",
    "👌 Clean Factory Fitting in Mirrors & Grille",
    "⚡ Zero Lag in Reverse Feed",
    "👍 Effortless Tight Parking"
  ],
  "✨ Interior Ambient Lights": [
    "✨ 64-Color App-Controlled Lighting",
    "👌 Concealed Fiber Optic Wiring",
    "🎵 Synced to Music Beats",
    "🛋️ Luxury Mercedes/Audi Style Cabin Glow",
    "🔌 Safe Fuse-Tap Power Connection",
    "🚗 Stunning Nighttime Ambience"
  ],
  "🛵 Full Periodic Bike Service": [
    "🚀 Butter-Smooth Engine Revs",
    "🛢️ Premium Motul/Castrol Synthetic Oil",
    "⚙️ Silky Smooth Gear Shifts",
    "🛑 Crisp Responsive Braking",
    "💯 100% Genuine OEM Spares Fitted",
    "⚡ Fast Same-Day Handover"
  ],
  "⛓️ Chain Cleaning & Lube": [
    "⛓️ Heavy-Duty Degreasing of Sprocket",
    "🛢️ High-Tack Synthetic Chain Lube Applied",
    "🎯 Exact Chain Slackness Adjusted",
    "🤫 Eliminated Drivetrain Chain Clatter",
    "👌 Extended Sprocket Life",
    "👍 Smooth Power Delivery"
  ],
  "🛑 Hydraulic Brake Bleeding": [
    "🛑 Fresh DOT4 Brake Fluid Flushed",
    "✨ Zero Sponge or Fade in Brake Lever",
    "💯 High-Bite Ceramic Brake Pads",
    "🛡️ Cleaned Disc Rotors & Calipers",
    "👍 Pinpoint Emergency Stopping",
    "👨‍🔧 Master Two-Wheeler Tech"
  ],
  "⛽ Fuel Injector / Carb Tuning": [
    "⛽ Ultrasonic Fuel Injector Cleaning",
    "🚀 Crisp Instant Throttle Pickup",
    "💨 Fixed Engine Misfiring & Idling Drops",
    "⛽ Noticeable Mileage Improvement",
    "🎯 Accurate CO/Lambda Emission Tuning",
    "👍 Revs Freely to Redline"
  ],
  "🧼 Foam Body Wash": [
    "🧼 Thick Snow Foam Cleansed Road Grease",
    "✨ Gloss Polish Applied on Tank & Fairings",
    "🛞 Black Tire Shine & Engine Dressing",
    "💨 Air-Gun Blown Dry Electrical Connectors",
    "👌 Spotless Chrome & Alloy Finish",
    "🛵 Looked Fresh out of Showroom"
  ],
  "⚡ Fast DC EV Charging": [
    "⚡ 60kW+ High-Speed DC Fast Charging",
    "🔋 20% to 80% Top-up in 35 Mins",
    "🔌 Heavy-Duty CCS2 Connector Gun",
    "📱 Seamless QR & RFID Card Payment",
    "🛡️ Safe Automated Thermal Cutoff",
    "🚗 Spacious Dedicated EV Parking Bay"
  ],
  "🔋 Battery Health Diagnostic": [
    "📊 Accurate State-of-Health (SoH) Report",
    "🔋 Individual Cell Voltage Balance Check",
    "🌡️ BMS Temperature Diagnostic Done",
    "💡 Battery Life Optimization Tips",
    "👨‍🔧 Certified EV Technician Guidance",
    "👍 Total Peace of Mind on Range"
  ],
  "🔌 Inverter & Wiring Check": [
    "🔌 High-Voltage Insulation Resistance Test",
    "🛡️ Cleaned High-Amp Contact Pins",
    "⚡ Checked Onboard Charger (OBC) Health",
    "👌 Zero Grounding or Earthing Faults",
    "👨‍🔧 High EV Safety Compliance",
    "👍 Safe Fast Charging"
  ],
  "💨 Tire Pressure Nitrogen Top-up": [
    "💨 Accurate EV Tire Pressure Inflation",
    "🚗 Optimized Rolling Resistance for Range",
    "❄️ Cooler Running Tires on Highways",
    "👌 Fast Digital Auto-Cutoff Gauge",
    "👍 Boosted Electric Range (km/kWh)",
    "⚡ Quick 2-Minute Service"
  ],
  "🧽 Windshield Cleaning": [
    "🧽 Clean Streak-Free Glass Cleaner",
    "💧 Filled Wiper Fluid Reservoir",
    "🌧️ Removed Bug Splatters & Dust",
    "👌 Crystal Clear Road Visibility",
    "😊 Complimentary Service While Charging",
    "👍 Great Thoughtful Touch"
  ],
  "👗 Designer Saree Collection": [
    "🧵 Pure Kanjivaram & Banarasi Silk",
    "✨ Intricate Zari & Thread Borders",
    "🎨 Exclusive Designer Color Shades",
    "👌 Lightweight & Drapes Elegantly",
    "👑 Royal Heritage Appeal",
    "💰 Honest Authentic Value"
  ],
  "👰 Bridal Lehenga": [
    "✨ Handcrafted Zardozi & Sequin Work",
    "👑 Stunning 16-Kali Flare & Can-Can",
    "👌 Custom Tailored to Exact Fit",
    "🎨 Gorgeous Trending Bridal Hues",
    "👰 Looked Like a Royal Bride",
    "📸 Spectacular in Wedding Photos"
  ],
  "👘 Partywear Kurti Set": [
    "🧵 Breathable Cotton & Chanderi Fabric",
    "✨ Elegant Cut & Neckline Embroidery",
    "👌 Includes Matching Pants & Dupatta",
    "🎨 Chic Contemporary Pastel Shades",
    "👗 Flattering Silhouette",
    "👍 Great for Festive Gatherings"
  ],
  "💃 Anarkali Suit": [
    "💃 Floor-Length Dramatic Royal Flare",
    "✨ Delicate Handwork on Bodice",
    "🧵 High-Quality Flowing Georgette",
    "👌 Comfortable Breathable Inner Lining",
    "👑 Head-Turning Party Look",
    "👌 Perfect Fitting Alterations Done"
  ],
  "🥻 Silk Dupatta": [
    "🥻 Rich Woven Zari Borders",
    "🧵 100% Pure Organza & Tussar Silk",
    "🎨 Hand-Dyed Artisanal Prints",
    "✨ Elevates Any Simple Kurti",
    "👌 Generous Length & Width",
    "🎁 Perfect Gift Choice"
  ],
  "🤵 3-Piece Tuxedo Suit": [
    "✂️ Bespoke Master Tailor Craftsmanship",
    "🧵 Premium Italian Wool & Satin Lapels",
    "👌 Flawless Shoulder & Chest Fit",
    "🤵 Crisp Modern Structured Silhouette",
    "✨ Luxury Inner Lining & Horn Buttons",
    "⏱️ Delivered Right on Schedule"
  ],
  "👔 Custom Fitted Shirts": [
    "👔 100% Egyptian Giza Cotton Fabric",
    "👌 Precise Collar & Cuff Measurements",
    "✂️ Clean Single-Needle Stitching",
    "✨ Monogrammed Initials Embroidery",
    "👔 Stays Crisp All Day Long",
    "👍 Flattering Slim Fit"
  ],
  "👖 Tailored Formal Trousers": [
    "👖 Razor-Sharp Front Crease",
    "👌 Exact Waist & Ankle Taper",
    "🧵 Comfortable Breathable Fabric",
    "✨ Quality YKK Zippers & Waist Hooks",
    "👌 Flawless Fall Over Shoes",
    "👍 Ultimate Office Comfort"
  ],
  "🧥 Italian Blazer": [
    "🧥 Unstructured Lightweight Fit",
    "🎨 Trendy Modern Textured Weave",
    "👌 Complemented Jeans & Chinos",
    "✨ Premium Horn Buttons",
    "🤵 Sharp Casual & Party Look",
    "👍 Great Versatile Wardrobe Piece"
  ],
  "👔 Sherwani & Kurta": [
    "👑 Royal Thread & Zari Hand-Embroidery",
    "🧵 Rich Raw Silk & Jacquard Fabric",
    "👌 Comfortable All-Day Wear for Groom",
    "🎨 Unique Heritage Color Tones",
    "✨ Matching Stole & Mojari Fit",
    "📸 Stunning in Wedding Pictures"
  ],
  "🏃 Running & Gym Shoes": [
    "☁️ Ultra-Responsive Foam Cushioning",
    "💨 Breathable Engineered Mesh Upper",
    "🏃 Superior Heel Support & Energy Return",
    "🛡️ High-Traction Anti-Slip Rubber Grip",
    "👌 Lightweight & Zero Bite",
    "💯 100% Original Brand Stock"
  ],
  "👟 Limited Edition Sneakers": [
    "👟 Rare Collectible Colorway in Stock",
    "💯 100% Verified Authentic Sneakers",
    "👌 Premium Suede & Leather Finish",
    "🎨 Iconic Streetwear Silhouette",
    "📦 Mint Condition Box & Extra Laces",
    "👍 Turn Heads Everywhere"
  ],
  "👡 Comfort Walking Sandals": [
    "👡 Orthopedic Memory Foam Footbed",
    "👌 Adjustable Soft Padded Straps",
    "☁️ All-Day Walking Comfort for Sore Feet",
    "🛡️ Durable Anti-Skid Soles",
    "👌 Stylish Yet Super Ergonomic",
    "👍 Perfect Daily Wear"
  ],
  "👞 Formal Leather Shoes": [
    "👞 Handcrafted Genuine Full-Grain Leather",
    "✨ Rich Mirror Gloss Patina Finish",
    "👌 Padded Heel Collar (No Shoe Bites)",
    "👔 Elegant Oxford & Brogue Styling",
    "🛡️ Solid Goodyear-Welted Durability",
    "👑 Pure Executive Class"
  ],
  "🧦 Cushioned Insoles": [
    "🧦 High-Density Memory Foam Cushioning",
    "🦶 Arch Support for Flat Feet & Plantar Fasciitis",
    "💨 Breathable Anti-Sweat Top Fabric",
    "👌 Easily Trimmed to Any Shoe Size",
    "✨ Instant Upgrade to Old Shoes",
    "👍 Inexpensive Comfort Miracle"
  ],
  "💍 Gold Bridal Necklace": [
    "🏷️ 100% 916 BIS Hallmarked Gold Purity",
    "✨ Intricate Filigree & Kundan Work",
    "👑 Grand Statement Piece for Brides",
    "⚖️ 100% Transparent Scale Weighing",
    "💰 Very Reasonable Making Charges",
    "📜 Official Certificate of Authenticity"
  ],
  "💎 Certified Diamond Solitaire Ring": [
    "💎 IGI/GIA Certified VVS-EF Diamonds",
    "✨ Dazzling Sparkle & Fire in Every Light",
    "💍 Precision 6-Prong Platinum/Gold Setting",
    "👌 Custom Ring Sizing to Perfection",
    "🎁 Luxury Velvet Box Packaging",
    "❤️ Perfect Proposal & Engagement Ring"
  ],
  "📿 Daily Wear Lightweight Gold": [
    "📿 Modern Minimalist Everyday Designs",
    "🛡️ Sturdy & Break-Resistant Chains",
    "✨ Subtle Elegance for Office Wear",
    "💰 Pocket-Friendly Gold Budgets",
    "👌 Skin-Friendly Hypoallergenic Finish",
    "🎁 Great Gift for Loved Ones"
  ],
  "🪙 Silver Bangles & Coins": [
    "🪙 92.5 Sterling Silver Hallmarked Purity",
    "✨ Tarnish-Resistant Rhodium Polish",
    "🎨 Traditional & Contemporary Styles",
    "⚖️ Exact Weight Stamped on Bar/Coin",
    "🎁 Ideal for Pujas & Auspicious Gifting",
    "👌 Smooth Hand Polished Finish"
  ],
  "👑 Antique Temple Jewelry": [
    "👑 Authentic Heritage Matt Gold Finish",
    "✨ Ruby, Emerald & Pearl Stone Studding",
    "🕉️ Auspicious Goddess Lakshmi Carvings",
    "👌 Master Goldsmith Handcraftsmanship",
    "👑 Regal Look with Silk Sarees",
    "👍 Heirloom Quality Jewelry"
  ],
  "📱 Latest 5G Smartphone": [
    "📦 100% Brand New Sealed Box",
    "🔄 Top Valuation for Old Phone Exchange",
    "⚡ Free Complete Data & Photo Migration",
    "🛡️ Free Premium Tempered Glass Applied",
    "💰 Matched Online Lowest Price",
    "📜 Official 1-Year Brand Warranty"
  ],
  "💻 Slim Laptop & Tablet": [
    "💻 Blazing Fast SSD & RAM Configuration",
    "🖥️ Crisp High-Res Anti-Glare Screen",
    "🔋 All-Day Battery Backup",
    "💡 Free Office Suite & Windows Setup",
    "🎁 Free Laptop Bag & Wireless Mouse",
    "👨‍💻 Expert Hardware Advice"
  ],
  "⌚ Smartwatch & Fitness Band": [
    "⌚ Accurate Heart Rate & SpO2 Tracking",
    "📱 Seamless Bluetooth Calling & Alerts",
    "🔋 Long 7-Day Battery Life",
    "✨ Bright AMOLED Always-On Display",
    "👌 Comfortable Sweatproof Silicone Strap",
    "💡 Fast Setup Assistance"
  ],
  "🎧 ANC Wireless Earbuds": [
    "🎧 Active Noise Cancellation (ANC)",
    "🎵 Deep Rich Bass & Clear Calls",
    "🔋 30+ Hours Playtime with Case",
    "🌧️ IPX5 Sweat & Water Resistance",
    "👌 Snug Ergonomic In-Ear Fit",
    "📱 Instant Bluetooth Pairing"
  ],
  "🔌 65W Fast Charger & Armor Case": [
    "⚡ 65W GaN Ultra-Fast Multiport Charger",
    "🛡️ Military-Grade Shockproof Armor Case",
    "🔌 Braided Tear-Proof Fast Charging Cable",
    "🛡️ Safe Surge & Heat Protection",
    "👌 Perfect Grip & Drop Protection",
    "💰 Great Combo Value"
  ],
  "🕶️ Polarized UV Sunglasses": [
    "☀️ 100% UV400 Sun Protection",
    "🌊 Polarized Glare-Free Driving Vision",
    "🕶️ Iconic Aviator & Wayfarer Shapes",
    "👌 Lightweight Scratch-Resistant Lenses",
    "🎁 Includes Hard Case & Lens Cloth",
    "👑 Instant Cool Style Factor"
  ],
  "👓 Titanium Lightweight Frames": [
    "☁️ Featherlight Weight on Nose Bridge",
    "🛡️ Flexible Memory Titanium (Unbreakable)",
    "👌 Zero Nosepad Marks or Headache",
    "🎨 Sleek Minimalist Modern Aesthetic",
    "💎 High-End Spring Hinges",
    "👍 All-Day Effortless Comfort"
  ],
  "💻 Blue-Ray Computer Glasses": [
    "💻 Blocks 99% Harmful Digital Blue Light",
    "✨ Eliminated Eye Fatigue & Dryness",
    "👌 Crystal Clear Non-Yellowing Lenses",
    "👓 Stylish Work-from-Home Frames",
    "🛡️ Anti-Reflective Coating Included",
    "👍 Must-Have for Screen Users"
  ],
  "👓 Progressive Zero-Power Frames": [
    "👓 Seamless Distance & Near Reading View",
    "✨ Zero Visible Bifocal Dividing Line",
    "🎯 Wide Distortion-Free Corridor",
    "👌 Custom Centered to Pupil Height",
    "💡 Quick 2-Day Adaptation Guarantee",
    "👨‍⚕️ Expert Fitting Precision"
  ],
  "✨ Contact Lens Solution": [
    "💧 All-in-One Disinfecting & Storing Solution",
    "✨ Multi-Action Protein Remover",
    "👁️ Keeps Lenses Moist All Day Long",
    "🌿 Gentle on Sensitive Eyes",
    "🎁 Free Lens Case Included",
    "👌 Trusted Quality Brand"
  ],
  "🛋️ Premium L-Shape Sofa": [
    "🛋️ High-Density 40D Foam Cushioning",
    "✨ Stain-Resistant Luxury Fabric/Leatherette",
    "🪵 Solid Termite-Treated Wood Frame",
    "👌 Ergonomic Lumbar & Neck Support",
    "🎨 Modern Contemporary Aesthetic",
    "📜 5-Year Structural Warranty",
    "🚚 Free Home Delivery & Setup"
  ],
  "🪑 Solid Sheesham Dining Table": [
    "🪵 100% Genuine Seasoned Sheesham Wood",
    "✨ Natural Rich Wood Grain & Smooth Polish",
    "🛠️ Heavy Solid Build (No Wobble)",
    "🪑 6 Ergonomically Padded Dining Chairs",
    "👌 Scratch-Resistant Table Top Finish",
    "👑 Grand Centerpiece for Dining Room"
  ],
  "🛏️ King Size Storage Bed": [
    "🛏️ Smooth Hydraulic Gas-Lift Storage Box",
    "🪵 Sturdy Heavy-Duty Engineered Wood Frame",
    "✨ Padded Cushioned Headboard for Reading",
    "👌 Zero Squeaking or Creaking Sound",
    "📦 Huge Clutter-Free Storage Space",
    "🛠️ Professional In-Home Carpenter Assembly"
  ],
  "🖼️ Modern Canvas Wall Art": [
    "🖼️ High-Definition UV Waterproof Print",
    "✨ Gallery Wrapped on Wooden Stretcher",
    "🎨 Vibrant Colors & Modern Aesthetic",
    "👌 Instant Luxury Upgrade to Living Room",
    "🔨 Ready to Hang Hardware Included",
    "👍 Elegant Home Decor Addition"
  ],
  "🛋️ Electric Recliner Chair": [
    "🛋️ Smooth Motorized Recline at Touch of Button",
    "☁️ Cloud-Like Plush Overstuffed Cushioning",
    "📱 Built-in USB Charging Port",
    "👌 Swivel & Rocking Functionality",
    "✨ Premium Breathable Leatherette",
    "😴 Ultimate Relaxation & TV Lounging"
  ],
  "🧩 Educational STEM Building Toys": [
    "🌿 100% Non-Toxic BPA-Free Plastic",
    "💡 Inspires Creativity & Problem Solving",
    "👌 Smooth Rounded Child-Safe Edges",
    "🧩 Hours of Screen-Free Brain Play",
    "📦 Reusable Sturdy Storage Box",
    "👍 Highly Engaging for Kids"
  ],
  "🏎️ Remote Control RC Supercar": [
    "🏎️ High-Speed Drift & 360° Spins",
    "🎮 Long-Range 2.4GHz Remote Control",
    "🔋 Rechargeable High-Capacity Battery Pack",
    "💡 Functional LED Headlights & Engine Sounds",
    "🛡️ Rugged Crash-Resistant Bumper",
    "🎁 Ultimate Birthday Gift"
  ],
  "👶 Ergonomic Baby Stroller": [
    "👶 5-Point Safety Harness & Bumper Bar",
    "☁️ Multi-Position Reclining Seat & Sun Canopy",
    "🚗 Compact 1-Hand Fold for Car Boot",
    "🛞 Smooth All-Terrain Shock Absorber Wheels",
    "🛍️ Huge Bottom Storage Basket",
    "🧼 Machine Washable Fabrics"
  ],
  "📚 Illustrated Story Books": [
    "📚 Vibrant Colorful Hardcover Illustrations",
    "📖 Engaging Bedtime & Moral Stories",
    "🧠 Boosts Vocabulary & Early Reading",
    "✨ Thick Tear-Resistant Glossy Paper",
    "👌 Age-Appropriate Themes",
    "👍 Loved by Young Readers"
  ],
  "🎨 Non-Toxic Art & Clay Kit": [
    "🌿 Safe Organic Wheat-Based Dough",
    "🎨 Bright Non-Staining Vibrant Colors",
    "✨ Includes Fun Cutters, Rollers & Molds",
    "👌 Keeps Kids Busy with Hands-On Craft",
    "🧼 Cleans Off Hands & Tables Easily",
    "🎁 Fun Creative Gift Kit"
  ],
  "🌸 Luxury Eau de Parfum (EDP)": [
    "⏱️ 12-Hour Long-Lasting Projection",
    "🌸 Intoxicating Floral & Oud Notes",
    "💎 Heavy Luxury Glass Atomizer Bottle",
    "👌 Zero Alcohol-Harsh Opening",
    "✨ Receives Non-Stop Compliments",
    "🎁 Beautiful Gift Packaging"
  ],
  "🧴 Vitamin C Brightening Serum": [
    "✨ Faded Dark Spots & Acne Scars",
    "🌿 20% Pure L-Ascorbic Acid & Ferulic",
    "💧 Lightweight Watery Quick-Absorb Feel",
    "👌 Non-Sticky Non-Greasy Radiance",
    "🛡️ Protected in Dark UV Glass Dropper",
    "💎 Noticeable Skin Glow in 2 Weeks"
  ],
  "🌿 Pure Organic Body Butter": [
    "🌿 100% Raw Shea & Cocoa Butter",
    "💧 48-Hour Intense Dry Skin Hydration",
    "🌸 Sweet Natural Vanilla & Almond Scent",
    "👌 Melts Instantly into Skin",
    "🌿 Cruelty-Free & Paraben-Free",
    "✨ Deep Velvet Softness"
  ],
  "🕯️ Scented Soy Wax Candle": [
    "🕯️ Clean Smoke-Free 100% Natural Soy Wax",
    "🌸 Fills Entire Room with Calming Aroma",
    "🪵 Crackling Wooden Wick Sound",
    "⏱️ Long 45+ Hours Clean Burn Time",
    "✨ Aesthetic Amber Glass Jar Decor",
    "🕊️ Creates Instant Relaxing Vibe"
  ],
  "🧼 Handmade Cold-Pressed Soaps": [
    "🧼 Rich Moisturizing Coconut & Olive Oil",
    "🌿 Infused with Real Herbs & Essential Oils",
    "👌 Rich Creamy Lather (Gentle on Skin)",
    "✨ Non-Drying Chemical-Free Cleansing",
    "🌸 Natural Subtle Earthy Fragrance",
    "👍 100% Biodegradable"
  ],
  "🍫 Artisanal Dark Chocolates": [
    "🍫 70%+ Single-Origin Cocoa Bean",
    "✨ Silky Smooth Bean-to-Bar Melt",
    "🍓 Infused with Sea Salt & Berries",
    "😋 Rich Complex Non-Bitter Flavor",
    "📦 Beautiful Gold Foil Packaging",
    "🎁 Decadent Gourmet Gift"
  ],
  "🧀 Imported European Cheese": [
    "🧀 Authentic Gouda, Brie & Parmesan Wheels",
    "❄️ Stored in Continuous Temperature Control",
    "😋 Rich Creamy Aged Pungency",
    "👌 Freshly Sliced & Vacuum Packed",
    "🍷 Perfect for Wine & Charcuterie Boards",
    "🌿 100% Genuine Import"
  ],
  "🌿 Exotic Pasta Sauces & Truffle Oil": [
    "🌿 Fragrant White Truffle Infusion",
    "🍅 Authentic Italian San Marzano Tomatoes",
    "😋 Deep Rich Restaurant-Quality Flavor",
    "👌 Zero Preservatives or Artificial Flavors",
    "🍝 Elevates Homemade Pasta Instantly",
    "👌 High Gourmet Standard"
  ],
  "☕ Single-Origin Arabica Beans": [
    "☕ 100% Estate Grown High-Altitude Arabica",
    "🔥 Freshly Roasted Whole Bean Batch",
    "😋 Notes of Caramel, Berry & Dark Cocoa",
    "💨 Aromatic Nitrogen-Flushed Valve Bag",
    "👌 Perfect for Moka Pot & Pour-Over",
    "☕ Barista Grade Brew at Home"
  ],
  "🍵 Organic Matcha Green Tea": [
    "🍵 Ceremonial Grade Japanese Green Tea",
    "🌿 Vibrant Emerald Green Micro-Powder",
    "⚡ Sustained Calm Energy & Antioxidants",
    "😋 Smooth Sweet Umami (Zero Bitterness)",
    "🍵 Whisks into Frothy Rich Latte",
    "👍 Super Healthy Superfood"
  ],
  "🌹 Fresh Rose Bouquet": [
    "🌹 Farm-Fresh Velvety Long-Stem Roses",
    "🌸 100% Fresh Blooms (Lasted 5+ Days)",
    "🎀 Korean Matte Paper & Satin Ribbon Wrap",
    "🌿 Fragrant Crisp Green Foliage",
    "⏱️ Punctual Same-Day Delivery",
    "💌 Handwritten Card Included",
    "❤️ Heartwarming Romantic Surprise"
  ],
  "🌸 Exotic Flower Basket": [
    "🌸 Fresh Orchids, Carnations & Lilies",
    "🧺 Handwoven Rustic Willow Basket",
    "💧 Wet Oasis Foam Kept Stems Hydrated",
    "🎨 Gorgeous Vibrant Color Arrangement",
    "✨ Perfect Centerpiece for Festivities",
    "👌 Exact Match to Online Photo"
  ],
  "💐 Custom Floral Box": [
    "💐 Luxurious Round Velvet Flower Box",
    "🌹 Symmetrically Arranged Fresh Roses",
    "🎀 Elegant Gold Foil Monogram Stamping",
    "👌 Mess-Free & No Vase Required",
    "🎁 High-End Premium Gift Presentation",
    "📸 Extremely Instagrammable Look"
  ],
  "🌿 Indoor Houseplants": [
    "🌿 Lush Green Air-Purifying Plants",
    "🪴 Premium Ceramic Planter Pot Included",
    "💡 Clear Watering & Sunlight Care Card",
    "🌱 Pest-Free Healthy Root System",
    "✨ Uplifts Living Room Decor Instantly",
    "👍 Long-Lasting Green Gift"
  ],
  "👰 Wedding Floral Decor": [
    "👰 Fresh Fragrant Jasmine & Rose Garlands",
    "🌸 Stunning Stage & Car Floral Styling",
    "✨ Long-Lasting Freshness All Evening",
    "⏱️ Installed Punctually Before Guests Arrived",
    "👑 Grand Traditional Elegance",
    "👌 Highly Professional Florist Team"
  ],
  "🎂 Flower & Cake Combo": [
    "🌹 Gorgeous Fresh Floral Bouquet",
    "🎂 Delicious Moist Cream Birthday Cake",
    "⏱️ Delivered Perfectly on the Stroke of Midnight",
    "📦 Safe Spill-Proof Transport Box",
    "🎁 Complete Celebration in One Order",
    "🎉 Made the Surprise Extra Special"
  ],
  "💼 Professional Service": [
    "✨ High Professional Competence",
    "⚡ Prompt & Timely Execution",
    "💡 Clear & Transparent Communication",
    "🤝 Honest Ethical Advice",
    "🎯 High Attention to Detail",
    "👍 Exceeded All Expectations"
  ],
  "🏋️ Fitness Training / Gym": [
    "🏋️ High-End Modern Gym Equipment",
    "💪 Dedicated Encouraging Personal Trainers",
    "🧼 Clean & Sanitized Workout Floor",
    "🥗 Practical Nutrition & Workout Plan",
    "🎵 High-Energy Workout Ambience",
    "✨ Noticeable Fitness Results"
  ],
  "🏨 Stay & Hospitality": [
    "🏨 Spotless Clean & Cozy Rooms",
    "🛏️ Ultra-Comfortable Plush Bedding",
    "🍳 Delicious Fresh Breakfast Spread",
    "😊 Courteous & Accommodating Staff",
    "⚡ Smooth Fast Check-in/Check-out",
    "👍 Wonderful Memorable Stay"
  ],
  "📸 Photography & Events": [
    "📸 Crystal-Clear High-Resolution Photos",
    "🎨 Creative Candid Angles & Lighting",
    "⏱️ Fast Turnaround for Edited Album",
    "😊 Friendly & Patient Photographers",
    "🎥 Cinematic 4K Video Quality",
    "💎 Captured Precious Memories Perfectly"
  ],
  "⚖️ Consultation & Legal": [
    "⚖️ Thorough In-Depth Case Analysis",
    "💡 Clear Actionable Legal Roadmap",
    "🤝 Transparent Fee Structure",
    "🔒 Complete Confidentiality Maintained",
    "⏱️ Punctual Consultation Timings",
    "👍 Highly Trusted Counsel"
  ],
  "🛠️ Custom Work": [
    "🛠️ Tailored Exactly to Client Specs",
    "✨ Superior Material Quality & Craftsmanship",
    "⏱️ Delivered Ahead of Deadline",
    "💡 Great Problem-Solving Ability",
    "💰 Fair & Justified Quote",
    "👍 Outstanding Finish"
  ]
};
