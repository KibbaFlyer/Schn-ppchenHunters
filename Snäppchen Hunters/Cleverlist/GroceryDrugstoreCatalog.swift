import Foundation

// Generic, brand-free shopping concepts. Quantities belong to ShoppingItem.
// IDs are permanent: never reuse a retired ID for a different product.
// Each row is id|type|section|Swedish|German|English.
enum GroceryDrugstoreCatalog {
    static let products: [Product] = {
        let products = rows.split(separator: "\n").map { row in
            let fields = row.split(separator: "|", omittingEmptySubsequences: false)
            precondition(fields.count == 6, "Invalid grocery catalog row")
            guard let id = Int(fields[0]),
                  let type = Int(fields[1]),
                  let section = Int(fields[2]) else {
                preconditionFailure("Invalid grocery catalog identifier")
            }
            return Product(
                id: stable(id),
                name: LocalizedName(sv: String(fields[3]), de: String(fields[4]), en: String(fields[5])),
                typeID: stable(type),
                sectionID: stable(section),
                modifiedAt: Date(timeIntervalSince1970: 0)
            )
        }
        precondition(Set(products.map(\.id)).count == products.count, "Duplicate grocery catalog IDs")
        precondition(Set(products.map { $0.name.sv.lowercased() }).count == products.count,
                     "Duplicate grocery catalog names")
        return products
    }()

    private static let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

    // Keep historical IDs resolvable for saved lists and older peers. This mapping
    // affects only untouched bundled records; user edits and tombstones remain intact.
    static func isUnmodifiedSeed(_ product: Product) -> Bool {
        product.revision == 0 && product.deviceID.isEmpty &&
            product.modifiedAt == Date(timeIntervalSince1970: 0)
    }

    static func isRetiredVariant(_ product: Product) -> Bool {
        guard isUnmodifiedSeed(product), let canonicalID = legacyIDs[product.id] else { return false }
        return canonicalID != product.id
    }

    static func consolidated(_ product: Product) -> Product {
        guard isUnmodifiedSeed(product),
              let canonical = productsByID[legacyIDs[product.id] ?? product.id] else { return product }
        var result = product
        // Preserve the historical ID so existing ShoppingItem references, quantities,
        // checked state and sync clocks are never rewritten by a catalog upgrade.
        result.name = canonical.name
        result.typeID = canonical.typeID
        result.sectionID = canonical.sectionID
        return result
    }

    private static let legacyIDs: [UUID: UUID] = {
        var result: [UUID: UUID] = [:]
        for row in legacyRanges.split(separator: "\n") {
            let fields = row.split(separator: "|").compactMap { Int($0) }
            precondition(fields.count == 3 && fields[0] <= fields[1], "Invalid legacy catalog range")
            let target = stable(fields[2])
            precondition(productsByID[target] != nil, "Missing canonical product")
            for number in fields[0]...fields[1] {
                precondition(result.updateValue(target, forKey: stable(number)) == nil,
                             "Overlapping legacy catalog ranges")
            }
        }
        return result
    }()

    private static func stable(_ number: Int) -> UUID {
        guard let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) else {
            preconditionFailure("Invalid seed UUID")
        }
        return id
    }

    private static let rows = """
    100|10|22|Mjölk|Milch|Milk
    101|10|22|Ägg|Eier|Eggs
    102|10|21|Bröd|Brot|Bread
    103|10|20|Bananer|Bananen|Bananas
    104|10|20|Äpplen|Äpfel|Apples
    105|10|20|Tomater|Tomaten|Tomatoes
    106|10|23|Pasta|Nudeln|Pasta
    107|10|23|Ris|Reis|Rice
    108|10|23|Kaffe|Kaffee|Coffee
    109|10|22|Ost|Käse|Cheese
    110|10|22|Yoghurt|Joghurt|Yogurt
    111|10|24|Glass|Eis|Ice cream
    112|11|25|Tandkräm|Zahnpasta|Toothpaste
    113|11|25|Schampo|Shampoo|Shampoo
    114|12|26|Diskmedel|Spülmittel|Dish soap
    115|10|20|Potatis|Kartoffeln|Potatoes
    116|10|22|Smör|Butter|Butter
    117|10|22|Havremjölk|Hafermilch|Oat milk
    118|12|25|Toalettpapper|Toilettenpapier|Toilet paper
    119|13|27|Strumpor|Socken|Socks
    1000|10|20|Päron|Birnen|Pears
    1001|10|20|Apelsiner|Orangen|Oranges
    1002|10|20|Clementiner|Clementinen|Clementines
    1003|10|20|Citroner|Zitronen|Lemons
    1004|10|20|Lime|Limetten|Limes
    1005|10|20|Grapefrukt|Grapefruits|Grapefruit
    1006|10|20|Vindruvor|Trauben|Grapes
    1007|10|20|Jordgubbar|Erdbeeren|Strawberries
    1008|10|20|Blåbär|Heidelbeeren|Blueberries
    1009|10|20|Hallon|Himbeeren|Raspberries
    1010|10|20|Björnbär|Brombeeren|Blackberries
    1011|10|20|Mango|Mangos|Mangoes
    1012|10|20|Ananas|Ananas|Pineapple
    1013|10|20|Kiwi|Kiwis|Kiwis
    1014|10|20|Persikor|Pfirsiche|Peaches
    1015|10|20|Nektariner|Nektarinen|Nectarines
    1016|10|20|Plommon|Pflaumen|Plums
    1017|10|20|Vattenmelon|Wassermelone|Watermelon
    1018|10|20|Honungsmelon|Honigmelone|Honeydew melon
    1019|10|20|Avokado|Avocados|Avocados
    1020|10|20|Gurka|Gurken|Cucumber
    1021|10|20|Paprika|Paprika|Bell peppers
    1022|10|20|Morötter|Karotten|Carrots
    1023|10|20|Gul lök|Gelbe Zwiebeln|Yellow onions
    1024|10|20|Rödlök|Rote Zwiebeln|Red onions
    1025|10|20|Vitlök|Knoblauch|Garlic
    1026|10|20|Purjolök|Lauch|Leeks
    1027|10|20|Salladslök|Frühlingszwiebeln|Spring onions
    1028|10|20|Broccoli|Brokkoli|Broccoli
    1029|10|20|Blomkål|Blumenkohl|Cauliflower
    1030|10|20|Vitkål|Weißkohl|White cabbage
    1031|10|20|Rödkål|Rotkohl|Red cabbage
    1032|10|20|Grönkål|Grünkohl|Kale
    1033|10|20|Spenat|Spinat|Spinach
    1034|10|20|Isbergssallad|Eisbergsalat|Iceberg lettuce
    1035|10|20|Ruccola|Rucola|Arugula
    1036|10|20|Zucchini|Zucchini|Zucchini
    1037|10|20|Aubergine|Aubergine|Eggplant
    1038|10|20|Champinjoner|Champignons|Button mushrooms
    1039|10|20|Sötpotatis|Süßkartoffeln|Sweet potatoes
    1040|10|20|Rödbetor|Rote Bete|Beetroot
    1041|10|20|Palsternacka|Pastinaken|Parsnips
    1042|10|20|Selleri|Staudensellerie|Celery
    1043|10|20|Sparris|Spargel|Asparagus
    1044|10|20|Ingefära|Ingwer|Ginger
    1045|10|20|Chili|Chilischoten|Chili peppers
    1046|10|20|Dill|Dill|Dill
    1047|10|20|Persilja|Petersilie|Parsley
    1048|10|20|Basilika|Basilikum|Basil
    1049|10|20|Koriander|Koriander|Cilantro
    1050|10|21|Rågbröd|Roggenbrot|Rye bread
    1051|10|21|Fullkornsbröd|Vollkornbrot|Wholegrain bread
    1052|10|21|Surdegsbröd|Sauerteigbrot|Sourdough bread
    1053|10|21|Formfranska|Toastbrot|Sandwich bread
    1054|10|21|Frallor|Brötchen|Bread rolls
    1055|10|21|Baguette|Baguette|Baguette
    1056|10|21|Knäckebröd|Knäckebrot|Crispbread
    1057|10|21|Tunnbröd|Fladenbrot|Flatbread
    1058|10|21|Pitabröd|Pitabrot|Pita bread
    1059|10|21|Tortillabröd|Tortillafladen|Tortilla wraps
    1060|10|21|Hamburgerbröd|Hamburgerbrötchen|Burger buns
    1061|10|21|Korvbröd|Hotdog-Brötchen|Hot dog buns
    1062|10|21|Croissanter|Croissants|Croissants
    1063|10|21|Kanelbullar|Zimtschnecken|Cinnamon buns
    1064|10|21|Muffins|Muffins|Muffins
    1065|10|21|Bagels|Bagels|Bagels
    1066|10|21|Riskakor|Reiswaffeln|Rice cakes
    1067|10|21|Skorpor|Zwieback|Rusks
    1068|10|21|Pepparkakor|Pfefferkuchen|Gingerbread biscuits
    1069|10|21|Havrekakor|Haferkekse|Oat cookies
    1070|10|22|Vispgrädde|Schlagsahne|Whipping cream
    1071|10|22|Matlagningsgrädde|Kochsahne|Cooking cream
    1072|10|22|Crème fraîche|Crème fraîche|Crème fraîche
    1073|10|22|Gräddfil|Saure Sahne|Sour cream
    1074|10|22|Filmjölk|Schwedenmilch|Swedish cultured milk
    1075|10|22|Kefir|Kefir|Kefir
    1076|10|22|Grekisk yoghurt|Griechischer Joghurt|Greek yogurt
    1077|10|22|Kvarg|Quark|Quark
    1078|10|22|Grynost|Hüttenkäse|Cottage cheese
    1079|10|22|Färskost|Frischkäse|Cream cheese
    1080|10|22|Mozzarella|Mozzarella|Mozzarella
    1081|10|22|Fetaost|Feta|Feta cheese
    1082|10|22|Parmesan|Parmesan|Parmesan
    1083|10|22|Halloumi|Halloumi|Halloumi
    1084|10|22|Brie|Brie|Brie
    1085|10|22|Cheddar|Cheddar|Cheddar
    1086|10|22|Riven ost|Geriebener Käse|Grated cheese
    1087|10|22|Margarin|Margarine|Margarine
    1088|10|22|Laktosfri mjölk|Laktosefreie Milch|Lactose-free milk
    1089|10|22|Sojadryck|Sojadrink|Soy drink
    1090|10|22|Mandeldryck|Mandeldrink|Almond drink
    1091|10|22|Havregrädde|Hafercreme|Oat cooking cream
    1092|10|22|Vaniljyoghurt|Vanillejoghurt|Vanilla yogurt
    1093|10|22|Fruktyoghurt|Fruchtjoghurt|Fruit yogurt
    1094|10|22|Smältost|Schmelzkäse|Processed cheese
    1095|10|40|Kycklingfilé|Hähnchenbrustfilet|Chicken breast
    1096|10|40|Kycklinglår|Hähnchenschenkel|Chicken thighs
    1097|10|40|Hel kyckling|Ganzes Hähnchen|Whole chicken
    1098|10|40|Kycklingvingar|Hähnchenflügel|Chicken wings
    1099|10|40|Nötfärs|Rinderhackfleisch|Ground beef
    1100|10|40|Blandfärs|Gemischtes Hackfleisch|Mixed ground meat
    1101|10|40|Fläskfärs|Schweinehackfleisch|Ground pork
    1102|10|40|Kycklingfärs|Hähnchenhackfleisch|Ground chicken
    1103|10|40|Fläskfilé|Schweinefilet|Pork tenderloin
    1104|10|40|Fläskkotletter|Schweinekoteletts|Pork chops
    1105|10|40|Fläskkarré|Schweinenacken|Pork neck
    1106|10|40|Bacon|Bacon|Bacon
    1107|10|40|Skinka|Schinken|Ham
    1108|10|40|Salami|Salami|Salami
    1109|10|40|Kalkonpålägg|Putenaufschnitt|Sliced turkey
    1110|10|40|Leverpastej|Leberpastete|Liver pâté
    1111|10|40|Falukorv|Falukorv|Swedish sausage
    1112|10|40|Wienerkorv|Wiener Würstchen|Wiener sausages
    1113|10|40|Grillkorv|Grillwürstchen|Grilling sausages
    1114|10|40|Chorizo|Chorizo|Chorizo
    1115|10|40|Köttbullar|Fleischbällchen|Meatballs
    1116|10|40|Nötstek|Rinderbraten|Beef roasting joint
    1117|10|40|Entrecôte|Entrecôte|Ribeye steak
    1118|10|40|Lammkotletter|Lammkoteletts|Lamb chops
    1119|10|40|Revbensspjäll|Rippchen|Pork ribs
    1120|10|41|Laxfilé|Lachsfilet|Salmon fillet
    1121|10|41|Torskfilé|Kabeljaufilet|Cod fillet
    1122|10|41|Sejfilé|Seelachsfilet|Saithe fillet
    1123|10|41|Rödspätta|Scholle|Plaice
    1124|10|41|Makrill|Makrele|Mackerel
    1125|10|41|Sill|Hering|Herring
    1126|10|41|Inlagd sill|Eingelegter Hering|Pickled herring
    1127|10|41|Rökt lax|Räucherlachs|Smoked salmon
    1128|10|41|Gravad lax|Graved Lachs|Cured salmon
    1129|10|41|Räkor|Garnelen|Shrimp
    1130|10|41|Kräftor|Flusskrebse|Crayfish
    1131|10|41|Musslor|Muscheln|Mussels
    1132|10|41|Fiskbullar|Fischklößchen|Fish balls
    1133|10|41|Kaviar på tub|Kaviarcreme|Fish roe spread
    1134|10|41|Tonfisk på burk|Thunfisch in Dosen|Canned tuna
    1135|10|23|Havregryn|Haferflocken|Rolled oats
    1136|10|23|Müsli|Müsli|Muesli
    1137|10|23|Granola|Knuspermüsli|Granola
    1138|10|23|Cornflakes|Cornflakes|Cornflakes
    1139|10|23|Vetemjöl|Weizenmehl|Wheat flour
    1140|10|23|Rågmjöl|Roggenmehl|Rye flour
    1141|10|23|Mandelmjöl|Mandelmehl|Almond flour
    1142|10|23|Strösocker|Kristallzucker|Granulated sugar
    1143|10|23|Florsocker|Puderzucker|Powdered sugar
    1144|10|23|Farinsocker|Brauner Zucker|Brown sugar
    1145|10|23|Vaniljsocker|Vanillezucker|Vanilla sugar
    1146|10|23|Bakpulver|Backpulver|Baking powder
    1147|10|23|Bikarbonat|Natron|Baking soda
    1148|10|23|Torrjäst|Trockenhefe|Dry yeast
    1149|10|23|Kakao|Kakaopulver|Cocoa powder
    1150|10|23|Honung|Honig|Honey
    1151|10|23|Sirap|Sirup|Syrup
    1152|10|23|Jordgubbssylt|Erdbeerkonfitüre|Strawberry jam
    1153|10|23|Lingonsylt|Preiselbeerkonfitüre|Lingonberry jam
    1154|10|23|Jordnötssmör|Erdnussbutter|Peanut butter
    1155|10|23|Chokladpålägg|Schokoladenaufstrich|Chocolate spread
    1156|10|23|Olivolja|Olivenöl|Olive oil
    1157|10|23|Rapsolja|Rapsöl|Rapeseed oil
    1158|10|23|Solrosolja|Sonnenblumenöl|Sunflower oil
    1159|10|23|Vinäger|Essig|Vinegar
    1160|10|23|Balsamvinäger|Balsamico-Essig|Balsamic vinegar
    1161|10|23|Sojasås|Sojasauce|Soy sauce
    1162|10|23|Ketchup|Ketchup|Ketchup
    1163|10|23|Senap|Senf|Mustard
    1164|10|23|Majonnäs|Mayonnaise|Mayonnaise
    1165|10|23|Pesto|Pesto|Pesto
    1166|10|23|Tomatpuré|Tomatenmark|Tomato paste
    1167|10|23|Krossade tomater|Gehackte Tomaten|Chopped tomatoes
    1168|10|23|Passerade tomater|Passierte Tomaten|Tomato passata
    1169|10|23|Kokosmjölk|Kokosmilch|Coconut milk
    1170|10|23|Kikärter|Kichererbsen|Chickpeas
    1171|10|23|Kidneybönor|Kidneybohnen|Kidney beans
    1172|10|23|Svarta bönor|Schwarze Bohnen|Black beans
    1173|10|23|Vita bönor|Weiße Bohnen|White beans
    1174|10|23|Röda linser|Rote Linsen|Red lentils
    1175|10|23|Gröna linser|Grüne Linsen|Green lentils
    1176|10|23|Majs på burk|Mais in Dosen|Canned corn
    1177|10|23|Oliver|Oliven|Olives
    1178|10|23|Saltgurka|Salzgurken|Dill pickles
    1179|10|23|Couscous|Couscous|Couscous
    1180|10|23|Bulgur|Bulgur|Bulgur
    1181|10|23|Quinoa|Quinoa|Quinoa
    1182|10|23|Glasnudlar|Glasnudeln|Glass noodles
    1183|10|23|Äggnudlar|Eiernudeln|Egg noodles
    1184|10|23|Lasagneplattor|Lasagneplatten|Lasagna sheets
    1185|10|23|Ströbröd|Paniermehl|Breadcrumbs
    1186|10|23|Salt|Salz|Salt
    1187|10|23|Svartpeppar|Schwarzer Pfeffer|Black pepper
    1188|10|23|Paprikapulver|Paprikapulver|Paprika powder
    1189|10|23|Curry|Currypulver|Curry powder
    1190|10|23|Spiskummin|Kreuzkümmel|Cumin
    1191|10|23|Kanel|Zimt|Cinnamon
    1192|10|23|Oregano|Oregano|Oregano
    1193|10|23|Timjan|Thymian|Thyme
    1194|10|23|Grönsaksbuljong|Gemüsebrühe|Vegetable stock
    1195|10|23|Kycklingbuljong|Hühnerbrühe|Chicken stock
    1196|10|23|Tacokrydda|Taco-Gewürz|Taco seasoning
    1197|10|23|Salsa|Salsa|Salsa
    1198|10|23|Tacoskal|Taco-Schalen|Taco shells
    1199|10|23|Torkade aprikoser|Getrocknete Aprikosen|Dried apricots
    1200|10|42|Apelsinjuice|Orangensaft|Orange juice
    1201|10|42|Äppeljuice|Apfelsaft|Apple juice
    1202|10|42|Multivitaminjuice|Multivitaminsaft|Multivitamin juice
    1203|10|42|Mineralvatten|Mineralwasser|Mineral water
    1204|10|42|Kolsyrat vatten|Sprudelwasser|Sparkling water
    1205|10|42|Cola|Cola|Cola
    1206|10|42|Lemonad|Zitronenlimonade|Lemonade
    1207|10|42|Saft|Fruchtsirup|Fruit cordial
    1208|10|42|Svart te|Schwarzer Tee|Black tea
    1209|10|42|Grönt te|Grüner Tee|Green tea
    1210|10|42|Örtte|Kräutertee|Herbal tea
    1211|10|42|Chokladdryckspulver|Trinkschokoladenpulver|Hot chocolate powder
    1212|10|42|Alkoholfri öl|Alkoholfreies Bier|Alcohol-free beer
    1213|10|42|Smoothie|Smoothie|Smoothie
    1214|10|42|Energidryck|Energydrink|Energy drink
    1215|10|24|Frysta ärter|Tiefkühlerbsen|Frozen peas
    1216|10|24|Fryst broccoli|Tiefkühlbrokkoli|Frozen broccoli
    1217|10|24|Fryst spenat|Tiefkühlspinat|Frozen spinach
    1218|10|24|Frysta hallon|Tiefkühlhimbeeren|Frozen raspberries
    1219|10|24|Frysta blåbär|Tiefkühlheidelbeeren|Frozen blueberries
    1220|10|24|Frysta jordgubbar|Tiefkühlerdbeeren|Frozen strawberries
    1221|10|24|Fryst mango|Tiefkühlmango|Frozen mango
    1222|10|24|Frysta grönsaksblandningar|Tiefkühlgemüsemischungen|Frozen mixed vegetables
    1223|10|24|Pommes frites|Pommes frites|French fries
    1224|10|24|Fryspizza|Tiefkühlpizza|Frozen pizza
    1225|10|24|Fiskpinnar|Fischstäbchen|Fish fingers
    1226|10|24|Kycklingnuggets|Hähnchennuggets|Chicken nuggets
    1227|10|24|Vegetariska burgare|Vegetarische Burger|Vegetarian burgers
    1228|10|24|Frysta dumplings|Tiefkühl-Dumplings|Frozen dumplings
    1229|10|24|Sorbet|Sorbet|Sorbet
    1230|11|25|Balsam|Haarspülung|Conditioner
    1231|11|25|Duschgel|Duschgel|Shower gel
    1232|11|25|Handtvål|Handseife|Hand soap
    1233|11|25|Deodorant|Deodorant|Deodorant
    1234|11|25|Tandborste|Zahnbürste|Toothbrush
    1235|11|25|Tandtråd|Zahnseide|Dental floss
    1236|11|25|Munskölj|Mundspülung|Mouthwash
    1237|11|25|Rakhyvlar|Rasierer|Razors
    1238|11|25|Rakgel|Rasiergel|Shaving gel
    1239|11|25|Hudkräm|Hautcreme|Skin cream
    1240|11|25|Solkräm|Sonnencreme|Sunscreen
    1241|11|25|Bomullsrondeller|Wattepads|Cotton pads
    1242|11|25|Bindor|Damenbinden|Sanitary pads
    1243|11|25|Tamponger|Tampons|Tampons
    1244|11|25|Blöjor|Windeln|Diapers
    1245|12|26|Hushållspapper|Küchenpapier|Paper towels
    1246|12|26|Tvättmedel|Waschmittel|Laundry detergent
    1247|12|26|Sköljmedel|Weichspüler|Fabric softener
    1248|12|26|Diskmaskinstabletter|Spülmaschinentabs|Dishwasher tablets
    1249|12|26|Diskborste|Spülbürste|Dish brush
    1250|12|26|Disksvampar|Spülschwämme|Dish sponges
    1251|12|26|Disktrasor|Spültücher|Dishcloths
    1252|12|26|Soppåsar|Müllbeutel|Trash bags
    1253|12|26|Fryspåsar|Gefrierbeutel|Freezer bags
    1254|12|26|Aluminiumfolie|Alufolie|Aluminum foil
    1255|12|26|Bakplåtspapper|Backpapier|Baking paper
    1256|12|26|Plastfolie|Frischhaltefolie|Cling film
    1257|12|26|Allrengöring|Allzweckreiniger|All-purpose cleaner
    1258|12|26|Fönsterputs|Glasreiniger|Glass cleaner
    1259|12|26|Toalettrengöring|WC-Reiniger|Toilet cleaner
    1260|10|43|Potatischips|Kartoffelchips|Potato chips
    1261|10|43|Tortillachips|Tortillachips|Tortilla chips
    1262|10|43|Popcorn|Popcorn|Popcorn
    1263|10|43|Salta pinnar|Salzstangen|Pretzel sticks
    1264|10|43|Mjölkchoklad|Milchschokolade|Milk chocolate
    1265|10|43|Mörk choklad|Zartbitterschokolade|Dark chocolate
    1266|10|43|Vit choklad|Weiße Schokolade|White chocolate
    1267|10|43|Gelégodis|Fruchtgummi|Gummy candy
    1268|10|43|Lakrits|Lakritz|Licorice
    1269|10|43|Tuggummi|Kaugummi|Chewing gum
    1270|10|43|Jordnötter|Erdnüsse|Peanuts
    1271|10|43|Cashewnötter|Cashewkerne|Cashews
    1272|10|43|Mandlar|Mandeln|Almonds
    1273|10|43|Valnötter|Walnüsse|Walnuts
    1274|10|43|Hasselnötter|Haselnüsse|Hazelnuts
    1275|10|43|Pistagenötter|Pistazien|Pistachios
    1276|10|43|Russin|Rosinen|Raisins
    1277|10|43|Dadlar|Datteln|Dates
    1278|10|43|Solrosfrön|Sonnenblumenkerne|Sunflower seeds
    1279|10|43|Pumpafrön|Kürbiskerne|Pumpkin seeds
    2000|10|23|Spaghetti|Spaghetti|Spaghetti
    2016|10|23|Penne|Penne|Penne
    2032|10|23|Fusilli|Fusilli|Fusilli
    2048|10|23|Rigatoni|Rigatoni|Rigatoni
    2064|10|23|Farfalle|Farfalle|Farfalle
    2080|10|23|Tagliatelle|Tagliatelle|Tagliatelle
    2096|10|23|Linguine|Linguine|Linguine
    2112|10|23|Makaroner|Makkaroni|Macaroni
    2128|10|23|Conchiglie|Conchiglie|Conchiglie
    2160|10|23|Basmatiris|Basmatireis|Basmati rice
    2168|10|23|Jasminris|Jasminreis|Jasmine rice
    2176|10|23|Sushiris|Sushireis|Sushi rice
    2184|10|23|Arborioris|Arborioreis|Arborio rice
    2192|10|23|Carnaroliris|Carnarolireis|Carnaroli rice
    2200|10|23|Rött ris|Roter Reis|Red rice
    2208|10|23|Svart ris|Schwarzer Reis|Black rice
    2216|10|23|Råris|Naturreis|Brown rice
    2224|10|23|Långkornigt ris|Langkornreis|Long-grain rice
    2232|10|23|Grötris|Milchreis (Reis)|Pudding rice
    2280|10|23|Hirs|Hirse|Millet
    2288|10|23|Bovete|Buchweizen|Buckwheat
    2296|10|23|Pärlkorn|Perlgraupen|Pearl barley
    2304|10|23|Amarant|Amaranth|Amaranth
    2312|10|23|Mathavre|Haferkörner|Oat groats
    2336|10|23|Bruna linser|Braune Linsen|Brown lentils
    2344|10|23|Belugalinser|Belugalinsen|Beluga lentils
    2352|10|23|Gula linser|Gelbe Linsen|Yellow lentils
    2360|10|23|Puy-linser|Puy-Linsen|Puy lentils
    2400|10|23|Cannellinibönor|Cannellinibohnen|Cannellini beans
    2408|10|23|Borlottibönor|Borlottibohnen|Borlotti beans
    2416|10|23|Pintobönor|Pintobohnen|Pinto beans
    2424|10|23|Mungbönor|Mungbohnen|Mung beans
    2432|10|23|Adzukibönor|Adzukibohnen|Adzuki beans
    2440|10|23|Svartögda bönor|Augenbohnen|Black-eyed peas
    2448|10|23|Sojabönor|Sojabohnen|Soybeans
    2456|10|23|Gula ärter|Gelbe Erbsen|Yellow peas
    2464|10|23|Gröna ärthalvor|Grüne Schälerbsen|Green split peas
    2472|10|23|Bondbönor|Ackerbohnen|Fava beans
    2488|10|23|Fullkornsvetemjöl|Weizenvollkornmehl|Whole wheat flour
    2504|10|23|Dinkelmjöl|Dinkelmehl|Spelt flour
    2512|10|23|Havremjöl|Hafermehl|Oat flour
    2520|10|23|Bovetemjöl|Buchweizenmehl|Buckwheat flour
    2528|10|23|Rismjöl|Reismehl|Rice flour
    2536|10|23|Klibbrismjöl|Klebreismehl|Glutinous rice flour
    2544|10|23|Majsmjöl|Maismehl|Corn flour
    2552|10|23|Kikärtsmjöl|Kichererbsenmehl|Chickpea flour
    2568|10|23|Kokosmjöl|Kokosmehl|Coconut flour
    2576|10|23|Teffmjöl|Teffmehl|Teff flour
    2584|10|23|Hirsmjöl|Hirsemehl|Millet flour
    2592|10|23|Sorghummjöl|Sorghummehl|Sorghum flour
    2600|10|23|Quinoamjöl|Quinoamehl|Quinoa flour
    2608|10|23|Kastanjemjöl|Kastanienmehl|Chestnut flour
    2616|10|23|Linsmjöl|Linsenmehl|Lentil flour
    2624|10|23|Sojamjöl|Sojamehl|Soy flour
    2632|10|23|Kornmjöl|Gerstenmehl|Barley flour
    2648|10|23|Malen vitpeppar|Gemahlener weißer Pfeffer|Ground white pepper
    2664|10|23|Malen ingefära|Gemahlener Ingwer|Ground ginger
    2672|10|23|Malen gurkmeja|Gemahlene Kurkuma|Ground turmeric
    2688|10|23|Malen koriander|Gemahlener Koriander|Ground coriander
    2696|10|23|Malen kardemumma|Gemahlener Kardamom|Ground cardamom
    2704|10|23|Malen muskot|Gemahlene Muskatnuss|Ground nutmeg
    2712|10|23|Malen kryddnejlika|Gemahlene Nelken|Ground cloves
    2728|10|23|Rökt paprikapulver|Geräuchertes Paprikapulver|Smoked paprika
    2736|10|23|Cayennepeppar|Cayennepfeffer|Cayenne pepper
    2744|10|23|Vitlökspulver|Knoblauchpulver|Garlic powder
    2752|10|23|Lökpulver|Zwiebelpulver|Onion powder
    2776|10|23|Torkad basilika|Getrocknetes Basilikum|Dried basil
    2784|10|23|Torkad rosmarin|Getrockneter Rosmarin|Dried rosemary
    2792|10|23|Torkad dill|Getrockneter Dill|Dried dill
    2880|10|43|Pekannötter|Pekannüsse|Pecans
    2896|10|43|Macadamianötter|Macadamianüsse|Macadamias
    2912|10|43|Paranötter|Paranüsse|Brazil nuts
    2944|10|43|Nötmix|Nussmischung|Mixed nuts
    2968|10|23|Torkade fikon|Getrocknete Feigen|Dried figs
    2984|10|23|Torkade plommon|Getrocknete Pflaumen|Prunes
    2992|10|23|Torkad mango|Getrocknete Mango|Dried mango
    3000|10|23|Torkad ananas|Getrocknete Ananas|Dried pineapple
    3008|10|23|Torkad papaya|Getrocknete Papaya|Dried papaya
    3016|10|23|Torkade bananskivor|Getrocknete Bananenscheiben|Dried banana slices
    3024|10|23|Torkade äppelringar|Getrocknete Apfelringe|Dried apple rings
    3032|10|23|Torkade päron|Getrocknete Birnen|Dried pears
    3040|10|23|Torkade persikor|Getrocknete Pfirsiche|Dried peaches
    3048|10|23|Torkade körsbär|Getrocknete Kirschen|Dried cherries
    3056|10|23|Torkade tranbär|Getrocknete Cranberrys|Dried cranberries
    3064|10|23|Torkade blåbär|Getrocknete Heidelbeeren|Dried blueberries
    3072|10|23|Torkade jordgubbar|Getrocknete Erdbeeren|Dried strawberries
    3080|10|23|Torkade gojibär|Getrocknete Gojibeeren|Dried goji berries
    3104|10|23|Korinter|Korinthen|Currants
    3112|10|23|Torkade mullbär|Getrocknete Maulbeeren|Dried mulberries
    3136|10|23|Hallonsylt|Himbeerkonfitüre|Raspberry jam
    3152|10|23|Blåbärssylt|Heidelbeerkonfitüre|Blueberry jam
    3168|10|23|Björnbärssylt|Brombeerkonfitüre|Blackberry jam
    3184|10|23|Aprikossylt|Aprikosenkonfitüre|Apricot jam
    3200|10|23|Persikosylt|Pfirsichkonfitüre|Peach jam
    3216|10|23|Körsbärssylt|Kirschkonfitüre|Cherry jam
    3232|10|23|Plommonsylt|Pflaumenkonfitüre|Plum jam
    3248|10|23|Svartvinbärssylt|Johannisbeerkonfitüre, schwarz|Blackcurrant jam
    3264|10|23|Krusbärssylt|Stachelbeerkonfitüre|Gooseberry jam
    3280|10|22|Jordgubbsyoghurt|Erdbeerjoghurt|Strawberry yogurt
    3296|10|22|Hallonyoghurt|Himbeerjoghurt|Raspberry yogurt
    3312|10|22|Blåbärsyoghurt|Heidelbeerjoghurt|Blueberry yogurt
    3328|10|22|Persikoyoghurt|Pfirsichjoghurt|Peach yogurt
    3344|10|22|Aprikosyoghurt|Aprikosenjoghurt|Apricot yogurt
    3360|10|22|Mangoyoghurt|Mangojoghurt|Mango yogurt
    3392|10|22|Körsbärsyoghurt|Kirschjoghurt|Cherry yogurt
    3408|10|22|Citronyoghurt|Zitronenjoghurt|Lemon yogurt
    3424|10|22|Bananyoghurt|Bananenjoghurt|Banana yogurt
    3440|10|24|Vaniljglass|Vanilleeis|Vanilla ice cream
    3456|10|24|Chokladglass|Schokoladeneis|Chocolate ice cream
    3472|10|24|Jordgubbsglass|Erdbeereis|Strawberry ice cream
    3488|10|24|Hallonglass|Himbeereis|Raspberry ice cream
    3504|10|24|Karamellglass|Karamelleis|Caramel ice cream
    3520|10|24|Kaffeglass|Kaffeeeis|Coffee ice cream
    3536|10|24|Pistageglass|Pistazieneis|Pistachio ice cream
    3552|10|24|Hasselnötsglass|Haselnusseis|Hazelnut ice cream
    3568|10|24|Mangoglass|Mangoeis|Mango ice cream
    3584|10|24|Kokosglass|Kokoseis|Coconut ice cream
    3616|10|42|Päronjuice|Birnensaft|Pear juice
    3632|10|42|Mangojuice|Mangosaft|Mango juice
    3648|10|42|Persikojuice|Pfirsichsaft|Peach juice
    3664|10|42|Aprikosjuice|Aprikosensaft|Apricot juice
    3680|10|42|Jordgubbsjuice|Erdbeersaft|Strawberry juice
    3696|10|42|Hallonjuice|Himbeersaft|Raspberry juice
    3712|10|42|Blåbärsjuice|Heidelbeersaft|Blueberry juice
    3728|10|42|Ananasjuice|Ananassaft|Pineapple juice
    3744|10|42|Svartvinbärsjuice|Schwarzer Johannisbeersaft|Blackcurrant juice
    3760|10|42|Assamte|Assam-Tee|Assam tea
    3768|10|42|Darjeelingte|Darjeeling-Tee|Darjeeling tea
    3776|10|42|Ceylonte|Ceylon-Tee|Ceylon tea
    3784|10|42|Earl Grey-te|Earl-Grey-Tee|Earl Grey tea
    3792|10|42|English Breakfast-te|English-Breakfast-Tee|English Breakfast tea
    3800|10|42|Sencha-te|Sencha-Tee|Sencha tea
    3808|10|42|Jasminte|Jasmintee|Jasmine tea
    3816|10|42|Gunpowder-te|Gunpowder-Tee|Gunpowder tea
    3824|10|42|Oolongte|Oolong-Tee|Oolong tea
    3832|10|42|Vitt te|Weißer Tee|White tea
    3840|10|42|Rooiboste|Rooibostee|Rooibos tea
    3848|10|42|Honeybushte|Honeybush-Tee|Honeybush tea
    3856|10|42|Pepparmyntste|Pfefferminztee|Peppermint tea
    3864|10|42|Kamomillte|Kamillentee|Chamomile tea
    3872|10|42|Fänkålste|Fencheltee|Fennel tea
    3880|10|42|Hibiskuste|Hibiskustee|Hibiscus tea
    3888|10|42|Nyponte|Hagebuttentee|Rosehip tea
    3896|10|42|Ingefärste|Ingwertee|Ginger tea
    3904|10|42|Citronmelisste|Melissentee|Lemon balm tea
    3912|10|42|Citrongräste|Zitronengrastee|Lemongrass tea
    4080|10|22|Gouda|Gouda|Gouda
    4088|10|22|Edamer|Edamer|Edam
    4096|10|22|Emmentaler|Emmentaler|Emmental
    4112|10|22|Gruyère|Gruyère|Gruyère
    4120|10|22|Maasdam|Maasdamer|Maasdam
    4136|10|22|Havarti|Havarti|Havarti
    4144|10|22|Prästost|Prästost|Präst cheese
    4152|10|22|Herrgårdsost|Herrgårdsost|Herrgård cheese
    4160|10|22|Grevé|Grevé|Grevé
    4176|10|22|Manchego|Manchego|Manchego
    4184|10|22|Provolone|Provolone|Provolone
    4192|10|22|Fontina|Fontina|Fontina
    4200|10|22|Monterey Jack|Monterey Jack|Monterey Jack
    4208|10|22|Tilsiter|Tilsiter|Tilsit
    4216|10|22|Bergkäse|Bergkäse|Alpine cheese
    4224|10|22|Comté|Comté|Comté
    4232|10|22|Racletteost|Raclettekäse|Raclette cheese
    4256|10|40|Kycklinglårfilé|Hähnchenoberkeulenfilet|Chicken thigh fillets
    4288|10|40|Kycklingklubbor|Hähnchenunterkeulen|Chicken drumsticks
    4304|10|40|Kalkonbröst|Putenbrust|Turkey breast
    4368|10|40|Nötstrimlor|Rindergeschnetzeltes|Beef strips
    4404|10|24|Fryst laxfilé|Tiefgekühlt: Lachsfilet|Frozen salmon fillet
    4412|10|24|Fryst torskfilé|Tiefgekühlt: Kabeljaufilet|Frozen cod fillet
    4420|10|24|Fryst sejfilé|Tiefgekühlt: Seelachsfilet|Frozen saithe fillet
    4424|10|41|Koljafilé|Schellfischfilet|Haddock fillets
    4428|10|24|Fryst koljafilé|Tiefgekühlt: Schellfischfilet|Frozen haddock fillets
    4432|10|41|Alaska pollock-filé|Alaska-Seelachsfilet|Alaska pollock fillets
    4436|10|24|Fryst alaska pollock-filé|Tiefgekühlt: Alaska-Seelachsfilet|Frozen alaska pollock fillets
    4440|10|41|Kummelfilé|Seehechtfilet|Hake fillets
    4444|10|24|Fryst kummelfilé|Tiefgekühlt: Seehechtfilet|Frozen hake fillets
    4448|10|41|Regnbågsfilé|Regenbogenforellenfilet|Rainbow trout fillets
    4452|10|24|Fryst regnbågsfilé|Tiefgekühlt: Regenbogenforellenfilet|Frozen rainbow trout fillets
    4456|10|41|Öringfilé|Forellenfilet|Trout fillets
    4460|10|24|Fryst öringfilé|Tiefgekühlt: Forellenfilet|Frozen trout fillets
    4464|10|41|Rödspättafilé|Schollenfilet|Plaice fillets
    4468|10|24|Fryst rödspättafilé|Tiefgekühlt: Schollenfilet|Frozen plaice fillets
    4472|10|41|Sjötungsfilé|Seezungenfilet|Sole fillets
    4476|10|24|Fryst sjötungsfilé|Tiefgekühlt: Seezungenfilet|Frozen sole fillets
    4480|10|41|Tilapiafilé|Tilapiafilet|Tilapia fillets
    4484|10|24|Fryst tilapiafilé|Tiefgekühlt: Tilapiafilet|Frozen tilapia fillets
    4488|10|41|Pangasiusfilé|Pangasiusfilet|Pangasius fillets
    4492|10|24|Fryst pangasiusfilé|Tiefgekühlt: Pangasiusfilet|Frozen pangasius fillets
    4496|10|41|Havsabborrefilé|Wolfsbarschfilet|Sea bass fillets
    4500|10|24|Fryst havsabborrefilé|Tiefgekühlt: Wolfsbarschfilet|Frozen sea bass fillets
    4504|10|41|Guldsparidfilé|Doradenfilet|Sea bream fillets
    4508|10|24|Fryst guldsparidfilé|Tiefgekühlt: Doradenfilet|Frozen sea bream fillets
    4512|10|41|Hälleflundrafilé|Heilbuttfilet|Halibut fillets
    4516|10|24|Fryst hälleflundrafilé|Tiefgekühlt: Heilbuttfilet|Frozen halibut fillets
    4520|10|41|Makrillfilé|Makrelenfilet|Mackerel fillets
    4524|10|24|Fryst makrillfilé|Tiefgekühlt: Makrelenfilet|Frozen mackerel fillets
    4528|10|41|Sillfilé|Heringsfilet|Herring fillets
    4532|10|24|Fryst sillfilé|Tiefgekühlt: Heringsfilet|Frozen herring fillets
    4536|10|41|Sardinfilé|Sardinenfilet|Sardine fillets
    4540|10|24|Fryst sardinfilé|Tiefgekühlt: Sardinenfilet|Frozen sardine fillets
    4544|10|41|Gösfilé|Zanderfilet|Pike-perch fillets
    4548|10|24|Fryst gösfilé|Tiefgekühlt: Zanderfilet|Frozen pike-perch fillets
    4552|10|41|Rödingfilé|Saiblingsfilet|Arctic char fillets
    4556|10|24|Fryst rödingfilé|Tiefgekühlt: Saiblingsfilet|Frozen arctic char fillets
    4572|10|24|Fryst blomkål|Tiefgekühlt: Blumenkohl|Frozen cauliflower
    4576|10|20|Brysselkål|Rosenkohl|Brussels sprouts
    4580|10|24|Fryst brysselkål|Tiefgekühlt: Rosenkohl|Frozen brussels sprouts
    4596|10|24|Fryst grönkål|Tiefgekühlt: Grünkohl|Frozen kale
    4600|10|20|Gröna bönor|Grüne Bohnen|Green beans
    4604|10|24|Frysta gröna bönor|Tiefgekühlt: Grüne Bohnen|Frozen green beans
    4608|10|20|Vaxbönor|Wachsbohnen|Wax beans
    4612|10|24|Frysta vaxbönor|Tiefgekühlt: Wachsbohnen|Frozen wax beans
    4616|10|20|Sockerärter|Zuckerschoten|Snow peas
    4620|10|24|Frysta sockerärter|Tiefgekühlt: Zuckerschoten|Frozen snow peas
    4624|10|20|Ärter|Grüne Erbsen|Green peas
    4632|10|20|Majskorn|Maiskörner|Sweetcorn kernels
    4636|10|24|Frysta majskorn|Tiefgekühlt: Maiskörner|Frozen sweetcorn kernels
    4644|10|24|Frysta morötter|Tiefgekühlt: Karotten|Frozen carrots
    4652|10|24|Fryst pumpa|Tiefgekühlt: Kürbis|Frozen pumpkin
    4660|10|24|Fryst sötpotatis|Tiefgekühlt: Süßkartoffeln|Frozen sweet potatoes
    4668|10|24|Fryst rotselleri|Tiefgekühlt: Knollensellerie|Frozen celeriac
    4676|10|24|Fryst purjolök|Tiefgekühlt: Lauch|Frozen leeks
    4684|10|24|Fryst paprika|Tiefgekühlt: Paprika|Frozen bell peppers
    4692|10|24|Frysta champinjoner|Tiefgekühlt: Champignons|Frozen button mushrooms
    4700|10|24|Fryst sparris|Tiefgekühlt: Spargel|Frozen asparagus
    4708|10|24|Fryst zucchini|Tiefgekühlt: Zucchini|Frozen zucchini
    4716|10|24|Fryst gul lök|Tiefgekühlt: Gelbe Zwiebeln|Frozen yellow onions
    4748|10|24|Frysta björnbär|Tiefgekühlt: Brombeeren|Frozen blackberries
    4752|10|20|Svarta vinbär|Schwarze Johannisbeeren|Blackcurrants
    4756|10|24|Frysta svarta vinbär|Tiefgekühlt: Schwarze Johannisbeeren|Frozen blackcurrants
    4760|10|20|Röda vinbär|Rote Johannisbeeren|Redcurrants
    4764|10|24|Frysta röda vinbär|Tiefgekühlt: Rote Johannisbeeren|Frozen redcurrants
    4768|10|20|Krusbär|Stachelbeeren|Gooseberries
    4772|10|24|Frysta krusbär|Tiefgekühlt: Stachelbeeren|Frozen gooseberries
    4780|10|24|Frysta körsbär|Tiefgekühlt: Kirschen|Frozen cherries
    4784|10|20|Tranbär|Cranberrys|Cranberries
    4788|10|24|Frysta tranbär|Tiefgekühlt: Cranberrys|Frozen cranberries
    4792|10|20|Lingon|Preiselbeeren|Lingonberries
    4796|10|24|Frysta lingon|Tiefgekühlt: Preiselbeeren|Frozen lingonberries
    4812|10|24|Fryst ananas|Tiefgekühlt: Ananas|Frozen pineapple
    4820|10|24|Frysta persikor|Tiefgekühlt: Pfirsiche|Frozen peaches
    4828|10|24|Frysta aprikoser|Tiefgekühlt: Aprikosen|Frozen apricots
    4836|10|24|Frysta plommon|Tiefgekühlt: Pflaumen|Frozen plums
    4840|10|20|Melonbitar|Melonenstücke|Melon chunks
    4844|10|24|Frysta melonbitar|Tiefgekühlt: Melonenstücke|Frozen melon chunks
    4852|10|24|Frysta bananer|Tiefgekühlt: Bananen|Frozen bananas
    4860|10|24|Frysta äpplen|Tiefgekühlt: Äpfel|Frozen apples
    4868|10|24|Frysta päron|Tiefgekühlt: Birnen|Frozen pears
    4876|10|24|Fryst papaya|Tiefgekühlt: Papaya|Frozen papaya
    4896|10|21|Vetebröd utan socker|Ungesüßtes Weizenbrot|Unsweetened wheat bread
    4912|10|21|Dinkelbröd|Dinkelbrot|Spelt bread
    4928|10|21|Havrebröd|Haferbrot|Oat bread
    4976|10|21|Flerkornsbröd|Mehrkornbrot|Multigrain bread
    4992|10|21|Solrosbröd|Sonnenblumenbrot|Sunflower bread
    5008|10|21|Pumpafröbröd|Kürbiskernbrot|Pumpkin seed bread
    5024|10|21|Linfröbröd|Leinsamenbrot|Flaxseed bread
    5040|10|43|Vetekex|Weizencracker|Wheat crackers
    5056|10|43|Rågkex|Roggencracker|Rye crackers
    5072|10|43|Dinkelkex|Dinkelcracker|Spelt crackers
    5088|10|43|Havrekex|Hafercracker|Oat crackers
    5104|10|43|Riskex|Reiscracker|Rice crackers
    5120|10|43|Majskex|Maiscracker|Corn crackers
    5136|10|43|Bovetekex|Buchweizencracker|Buckwheat crackers
    5152|10|43|Kikärtskex|Kichererbsencracker|Chickpea crackers
    5168|10|43|Linskex|Linsencracker|Lentil crackers
    5184|10|43|Flerkornskex|Mehrkorncracker|Multigrain crackers
    5200|10|43|Choklad med hasselnötter|Schokolade mit Haselnüssen|Chocolate with hazelnuts
    5216|10|43|Choklad med mandlar|Schokolade mit Mandeln|Chocolate with almonds
    5232|10|43|Choklad med pistage|Schokolade mit Pistazien|Chocolate with pistachios
    5248|10|43|Choklad med kokos|Schokolade mit Kokos|Chocolate with coconut
    5264|10|43|Choklad med apelsin|Schokolade mit Orange|Chocolate with orange
    5280|10|43|Choklad med mint|Schokolade mit Minze|Chocolate with mint
    5296|10|43|Choklad med hallon|Schokolade mit Himbeeren|Chocolate with raspberries
    5312|10|43|Choklad med jordgubbar|Schokolade mit Erdbeeren|Chocolate with strawberries
    5328|10|43|Choklad med karamell|Schokolade mit Karamell|Chocolate with caramel
    5344|10|43|Choklad med kaffe|Schokolade mit Kaffee|Chocolate with coffee
    5360|10|23|Tomatsoppa|Tomatensuppe|Tomato soup
    5368|10|23|Linssoppa|Linsensuppe|Lentil soup
    5376|10|23|Ärtsoppa|Erbsensuppe|Pea soup
    5384|10|23|Svampsoppa|Pilzsuppe|Mushroom soup
    5392|10|23|Pumpasoppa|Kürbissuppe|Pumpkin soup
    5400|10|23|Morotssoppa|Karottensuppe|Carrot soup
    5408|10|23|Broccolisoppa|Brokkolisuppe|Broccoli soup
    5416|10|23|Blomkålssoppa|Blumenkohlsuppe|Cauliflower soup
    5424|10|23|Potatis- och purjolökssoppa|Kartoffel-Lauch-Suppe|Potato and leek soup
    5432|10|23|Minestrone|Minestrone|Minestrone
    5440|10|23|Kycklingsoppa|Hühnersuppe|Chicken soup
    5448|10|23|Kycklingnudelsoppa|Hühner-Nudelsuppe|Chicken noodle soup
    5456|10|23|Gulaschsoppa|Gulaschsuppe|Goulash soup
    5464|10|23|Löksoppa|Zwiebelsuppe|Onion soup
    5472|10|23|Spenatsoppa|Spinatsuppe|Spinach soup
    5480|10|23|Sparrissoppa|Spargelsuppe|Asparagus soup
    5488|10|23|Bönsoppa|Bohnensuppe|Bean soup
    5496|10|23|Majssoppa|Maissuppe|Corn soup
    5504|10|23|Rödbetssoppa|Rote-Bete-Suppe|Beetroot soup
    5512|10|23|Sötpotatissoppa|Süßkartoffelsuppe|Sweet potato soup
    5520|10|23|Tomat- och basilikasås|Tomaten-Basilikum-Sauce|Tomato and basil sauce
    5528|10|23|Arrabbiatasås|Arrabbiata-Sauce|Arrabbiata sauce
    5536|10|23|Bolognesesås|Bolognese-Sauce|Bolognese sauce
    5544|10|23|Vegetarisk bolognesesås|Vegetarische Bolognese-Sauce|Vegetarian Bolognese sauce
    5552|10|23|Svamppastasås|Pilz-Pastasauce|Mushroom pasta sauce
    5560|10|23|Ostpastasås|Käse-Pastasauce|Cheese pasta sauce
    5568|10|23|Vodkapastasås|Wodka-Pastasauce|Vodka pasta sauce
    5576|10|23|Olivpastasås|Oliven-Pastasauce|Olive pasta sauce
    5584|10|23|Puttanescasås|Puttanesca-Sauce|Puttanesca sauce
    5592|10|23|Auberginepastasås|Auberginen-Pastasauce|Eggplant pasta sauce
    5600|10|23|Kormasås|Korma-Sauce|Korma sauce
    5608|10|23|Tikka masalasås|Tikka-Masala-Sauce|Tikka masala sauce
    5616|10|23|Jalfrezisås|Jalfrezi-Sauce|Jalfrezi sauce
    5624|10|23|Madras currysås|Madras-Currysauce|Madras curry sauce
    5632|10|23|Sötsur sås|Süßsaure Sauce|Sweet and sour sauce
    5640|10|23|Svartbönsås|Schwarzbohnensauce|Black bean sauce
    5648|10|23|Teriyakisås|Teriyakisauce|Teriyaki sauce
    5656|10|23|Sataysås|Sataysauce|Satay sauce
    5664|10|23|Grön thailändsk currysås|Grüne Thai-Currysauce|Thai green curry sauce
    5672|10|23|Röd thailändsk currysås|Rote Thai-Currysauce|Thai red curry sauce
    5696|10|23|Dinkelgranola|Dinkelgranola|Spelt granola
    5712|10|23|Bovetegranola|Buchweizengranola|Buckwheat granola
    5728|10|23|Quinoagranola|Quinoagranola|Quinoa granola
    5760|10|23|Dinkelmüsli|Dinkelmüsli|Spelt muesli
    5776|10|23|Flerkornsmüsli|Mehrkornmüsli|Multigrain muesli
    5792|10|23|Glutenfri müsli|Glutenfreies Müsli|Gluten-free muesli
    5808|10|23|Krispiga risflingor|Knusprige Reisflocken|Crispy rice cereal
    5824|10|23|Fullkornsflingor|Vollkornflocken|Wholegrain cereal
    5840|10|23|Äppelpuré för barn|Apfelpüree für Babys|Baby apple puree
    5848|10|23|Päronpuré för barn|Birnenpüree für Babys|Baby pear puree
    5856|10|23|Mangopuré för barn|Mangopüree für Babys|Baby mango puree
    5864|10|23|Bananpuré för barn|Bananenpüree für Babys|Baby banana puree
    5872|10|23|Persikopuré för barn|Pfirsichpüree für Babys|Baby peach puree
    5880|10|23|Aprikospuré för barn|Aprikosenpüree für Babys|Baby apricot puree
    5888|10|23|Äppel- och päronpuré för barn|Apfel-Birnen-Püree für Babys|Baby apple and pear puree
    5896|10|23|Äppel- och blåbärspuré för barn|Apfel-Heidelbeer-Püree für Babys|Baby apple and blueberry puree
    5904|10|23|Banan- och jordgubbspuré för barn|Bananen-Erdbeer-Püree für Babys|Baby banana and strawberry puree
    5912|10|23|Mango- och bananpuré för barn|Mango-Bananen-Püree für Babys|Baby mango and banana puree
    5920|10|23|Morotspuré för barn|Karottenpüree für Babys|Baby carrot puree
    5928|10|23|Pumpapuré för barn|Kürbispüree für Babys|Baby pumpkin puree
    5936|10|23|Sötpotatispuré för barn|Süßkartoffelpüree für Babys|Baby sweet potato puree
    5944|10|23|Ärtpuré för barn|Erbsenpüree für Babys|Baby pea puree
    5952|10|23|Palsternackspuré för barn|Pastinakenpüree für Babys|Baby parsnip puree
    5960|10|23|Broccoli- och potatispuré för barn|Brokkoli-Kartoffel-Püree für Babys|Baby broccoli and potato puree
    5968|10|23|Morots- och potatispuré för barn|Karotten-Kartoffel-Püree für Babys|Baby carrot and potato puree
    5976|10|23|Pumpa- och morotspuré för barn|Kürbis-Karotten-Püree für Babys|Baby pumpkin and carrot puree
    5984|10|23|Zucchini- och potatispuré för barn|Zucchini-Kartoffel-Püree für Babys|Baby zucchini and potato puree
    5992|10|23|Blomkåls- och potatispuré för barn|Blumenkohl-Kartoffel-Püree für Babys|Baby cauliflower and potato puree
    6040|11|25|Hårinpackning|Haarmaske|Hair mask
    6060|11|25|Leave-in-balsam|Leave-in-Spülung|Leave-in conditioner
    6080|11|25|Hårserum|Haarserum|Hair serum
    6180|11|25|Badskum|Schaumbad|Bubble bath
    6200|11|25|Ansiktsrengöring|Gesichtsreiniger|Facial cleanser
    6220|11|25|Ansiktsvatten|Gesichtswasser|Facial toner
    6240|11|25|Dagkräm|Tagescreme|Day cream
    6260|11|25|Nattkräm|Nachtcreme|Night cream
    6280|11|25|Ansiktsmask|Gesichtsmaske|Face mask
    6300|11|25|Handkräm|Handcreme|Hand cream
    6340|11|25|Fotkräm|Fußcreme|Foot cream
    6820|12|26|Golvrengöring|Bodenreiniger|Floor cleaner
    6840|12|26|Badrumsrengöring|Badreiniger|Bathroom cleaner
    7000|10|20|Rotselleri|Knollensellerie|Celeriac
    7001|10|20|Kålrot|Steckrübe|Swede
    7002|10|20|Rädisor|Radieschen|Radishes
    7003|10|20|Rättika|Rettich|Daikon
    7004|10|20|Kålrabbi|Kohlrabi|Kohlrabi
    7005|10|20|Fänkål|Fenchel|Fennel
    7006|10|20|Pak choi|Pak Choi|Bok choy
    7007|10|20|Romansallad|Römersalat|Romaine lettuce
    7008|10|20|Hjärtsallad|Mini-Römersalat|Little gem lettuce
    7009|10|20|Endive|Endivie|Endive
    7010|10|20|Fältsallad|Feldsalat|Lamb's lettuce
    7011|10|20|Salladsmix|Salatmischung|Mixed salad leaves
    7012|10|20|Körsbärstomater|Kirschtomaten|Cherry tomatoes
    7013|10|20|Spenatblad|Babyspinat|Baby spinach
    7014|10|20|Schalottenlök|Schalotten|Shallots
    7015|10|20|Silverlök|Weiße Zwiebeln|White onions
    7016|10|20|Pumpa|Kürbis|Pumpkin
    7017|10|20|Butternutpumpa|Butternusskürbis|Butternut squash
    7018|10|20|Spetskål|Spitzkohl|Pointed cabbage
    7019|10|20|Savojkål|Wirsing|Savoy cabbage
    7020|10|20|Salladskål|Chinakohl|Chinese cabbage
    7021|10|20|Jordärtskocka|Topinambur|Jerusalem artichoke
    7022|10|20|Kronärtskocka|Artischocke|Artichoke
    7023|10|20|Pepparrot|Meerrettich|Horseradish
    7024|10|20|Majskolvar|Maiskolben|Corn on the cob
    7025|10|20|Böngroddar|Bohnensprossen|Bean sprouts
    7026|10|20|Alfalfagroddar|Alfalfasprossen|Alfalfa sprouts
    7027|10|20|Salladsärter|Zuckererbsen|Sugar snap peas
    7028|10|20|Kantareller|Pfifferlinge|Chanterelles
    7029|10|20|Ostronskivling|Austernpilze|Oyster mushrooms
    7030|10|20|Shiitake|Shiitake|Shiitake mushrooms
    7031|10|20|Portabello|Portobello|Portobello mushrooms
    7032|10|20|Gräslök|Schnittlauch|Chives
    7033|10|20|Mynta|Minze|Mint
    7034|10|20|Rosmarin|Rosmarin|Rosemary
    7035|10|20|Salvia|Salbei|Sage
    7036|10|20|Dragon|Estragon|Tarragon
    7037|10|20|Citronmeliss|Zitronenmelisse|Lemon balm
    7038|10|20|Citrongräs|Zitronengras|Lemongrass
    7039|10|20|Gurkmeja|Kurkuma|Turmeric root
    7040|10|20|Granatäpple|Granatapfel|Pomegranate
    7041|10|20|Passionsfrukt|Passionsfrucht|Passion fruit
    7042|10|20|Papaya|Papaya|Papaya
    7043|10|20|Aprikoser|Aprikosen|Apricots
    7044|10|20|Körsbär|Kirschen|Cherries
    7045|10|20|Fikon|Feigen|Fresh figs
    7046|10|20|Sharonfrukt|Kaki|Persimmon
    7047|10|20|Physalis|Physalis|Physalis
    7048|10|20|Pomelo|Pomelo|Pomelo
    7049|10|20|Blodapelsiner|Blutorangen|Blood oranges
    7050|10|20|Mandariner|Mandarinen|Mandarins
    7051|10|20|Cantaloupemelon|Cantaloupe-Melone|Cantaloupe melon
    7052|10|20|Kokosnöt|Kokosnuss|Coconut
    7053|10|20|Rabarber|Rhabarber|Rhubarb
    7054|10|20|Hjortron|Moltebeeren|Cloudberries
    7055|10|40|Oxfilé|Rinderfilet|Beef tenderloin
    7056|10|40|Ryggbiff|Rumpsteak|Sirloin steak
    7057|10|40|Högrev|Rindernacken|Beef chuck
    7058|10|40|Fransyska|Rinderkugel|Beef knuckle
    7059|10|40|Lövbiff|Dünne Rinderschnitzel|Minute steak
    7060|10|40|Grytbitar av nöt|Rindergulasch|Diced stewing beef
    7061|10|40|Oxbringa|Rinderbrust|Beef brisket
    7062|10|40|Fläsksida|Schweinebauch|Pork belly
    7063|10|40|Fläsklägg|Schweinshaxe|Pork shank
    7064|10|40|Rimmat fläsk|Gepökeltes Schweinefleisch|Salt pork
    7065|10|40|Fläskstek|Schweinebraten|Pork roasting joint
    7066|10|40|Lammfärs|Lammhackfleisch|Ground lamb
    7067|10|40|Lammstek|Lammkeule|Leg of lamb
    7068|10|40|Lammlägg|Lammhaxe|Lamb shank
    7069|10|40|Lammracks|Lammkarree|Rack of lamb
    7070|10|40|Kalvfärs|Kalbshackfleisch|Ground veal
    7071|10|40|Kalvschnitzel|Kalbsschnitzel|Veal schnitzel
    7072|10|40|Älgfärs|Elchhackfleisch|Ground elk
    7073|10|40|Renskav|Rentiergeschnetzeltes|Shaved reindeer meat
    7074|10|40|Viltgrytbitar|Wildgulasch|Diced game meat
    7075|10|40|Ankbröst|Entenbrust|Duck breast
    7076|10|40|Hel kalkon|Ganze Pute|Whole turkey
    7077|10|40|Kalkonfärs|Putenhackfleisch|Ground turkey
    7078|10|40|Kycklinglever|Hähnchenleber|Chicken liver
    7079|10|40|Nötlever|Rinderleber|Beef liver
    7080|10|40|Isterband|Isterband|Swedish smoked pork sausage
    7081|10|40|Prinskorv|Kleine Bratwürstchen|Small Swedish sausages
    7082|10|40|Salsiccia|Salsiccia|Salsiccia sausage
    7083|10|40|Bratwurst|Bratwurst|Bratwurst
    7084|10|40|Blodpudding|Blutpudding|Black pudding
    7085|10|40|Mortadella|Mortadella|Mortadella
    7086|10|40|Lufttorkad skinka|Luftgetrockneter Schinken|Dry-cured ham
    7087|10|40|Pancetta|Pancetta|Pancetta
    7088|10|40|Hamburgare|Burger-Patties|Beef burgers
    7089|10|40|Pulled pork|Pulled Pork|Pulled pork
    7090|10|41|Färsk tonfisk|Frischer Thunfisch|Fresh tuna
    7091|10|41|Strömming|Ostseehering|Baltic herring
    7092|10|41|Abborre|Flussbarsch|Perch
    7093|10|41|Fiskfärs|Fischhack|Minced fish
    7094|10|41|Bläckfisk|Tintenfisch|Squid
    7095|10|41|Pilgrimsmusslor|Jakobsmuscheln|Scallops
    7096|10|41|Hummer|Hummer|Lobster
    7097|10|41|Krabba|Krabbe|Crab
    7098|10|41|Havskräftor|Kaisergranat|Langoustines
    7099|10|41|Ostron|Austern|Oysters
    7100|10|41|Rom|Fischrogen|Fish roe
    7101|10|41|Ansjovis|Schwedische Ansjovis|Swedish spiced sprats
    7102|10|41|Sardiner på burk|Sardinen in Dosen|Canned sardines
    7103|10|41|Makrill i tomatsås|Makrele in Tomatensauce|Mackerel in tomato sauce
    7104|10|41|Surimi|Surimi|Surimi
    7105|10|22|Tofu|Tofu|Tofu
    7106|10|22|Tempeh|Tempeh|Tempeh
    7107|10|22|Seitan|Seitan|Seitan
    7108|10|22|Vegofärs|Vegetarisches Hack|Vegetarian mince
    7109|10|22|Vegokorv|Vegetarische Würstchen|Vegetarian sausages
    7110|10|22|Havreyoghurt|Haferjoghurt|Oat yogurt
    7111|10|22|Sojayoghurt|Sojajoghurt|Soy yogurt
    7112|10|22|Kokosyoghurt|Kokosjoghurt|Coconut yogurt
    7113|10|22|Laktosfri yoghurt|Laktosefreier Joghurt|Lactose-free yogurt
    7114|10|22|Laktosfri grädde|Laktosefreie Sahne|Lactose-free cream
    7115|10|22|Laktosfri crème fraîche|Laktosefreie Crème fraîche|Lactose-free crème fraîche
    7116|10|22|Laktosfritt smör|Laktosefreie Butter|Lactose-free butter
    7117|10|22|Ricotta|Ricotta|Ricotta
    7118|10|22|Mascarpone|Mascarpone|Mascarpone
    7119|10|22|Burrata|Burrata|Burrata
    7120|10|22|Getost|Ziegenkäse|Goat cheese
    7121|10|22|Blåmögelost|Blauschimmelkäse|Blue cheese
    7122|10|22|Camembert|Camembert|Camembert
    7123|10|22|Lagrad ost|Gereifter Käse|Mature cheese
    7124|10|22|Paneer|Paneer|Paneer
    7125|10|22|Vaniljsås|Vanillesauce|Vanilla sauce
    7126|10|22|Risgrynsgröt|Milchreis|Rice pudding
    7127|10|22|Chokladpudding|Schokoladenpudding|Chocolate pudding
    7128|10|22|Färsk jäst|Frische Hefe|Fresh yeast
    7129|10|22|Smördeg|Blätterteig|Puff pastry
    7130|10|22|Filodeg|Filoteig|Filo pastry
    7131|10|22|Pizzadeg|Pizzateig|Pizza dough
    7132|10|22|Hummus|Hummus|Hummus
    7133|10|22|Guacamole|Guacamole|Guacamole
    7134|10|22|Tzatziki|Tsatsiki|Tzatziki
    7135|10|22|Potatissallad|Kartoffelsalat|Potato salad
    7136|10|22|Rödbetssallad|Rote-Bete-Salat|Beetroot salad
    7137|10|22|Coleslaw|Coleslaw|Coleslaw
    7138|10|21|Glutenfritt bröd|Glutenfreies Brot|Gluten-free bread
    7139|10|21|Glutenfritt knäckebröd|Glutenfreies Knäckebrot|Gluten-free crispbread
    7140|10|21|Naanbröd|Naanbrot|Naan bread
    7141|10|21|Focaccia|Focaccia|Focaccia
    7142|10|21|Ciabatta|Ciabatta|Ciabatta
    7143|10|21|Rågsiktsbröd|Roggenmischbrot|Rye and wheat bread
    7144|10|21|Vörtbröd|Malzbrot|Swedish malt bread
    7146|10|21|Kardemummabullar|Kardamombrötchen|Cardamom buns
    7147|10|21|Lussekatter|Safrangebäck|Saffron buns
    7148|10|21|Semlor|Schwedische Sahnebrötchen|Swedish cream buns
    7149|10|21|Sockerkaka|Rührkuchen|Sponge cake
    7150|10|21|Kladdkaka|Schwedischer Schokoladenkuchen|Swedish sticky chocolate cake
    7151|10|21|Chokladbollar|Schokoladen-Hafer-Kugeln|Chocolate oat balls
    7152|10|23|Potatismjöl|Kartoffelstärke|Potato starch
    7153|10|23|Majsstärkelse|Maisstärke|Cornstarch
    7154|10|23|Mannagryn|Grieß|Semolina
    7155|10|23|Pärlsocker|Hagelzucker|Pearl sugar
    7156|10|23|Gelatin|Gelatine|Gelatin
    7157|10|23|Agar-agar|Agar-Agar|Agar agar
    7158|10|23|Pektin|Pektin|Pectin
    7159|10|23|Vaniljstång|Vanilleschote|Vanilla pod
    7160|10|23|Saffran|Safran|Saffron
    7161|10|23|Kokosflingor|Kokosraspel|Desiccated coconut
    7162|10|23|Sesamfrön|Sesamsamen|Sesame seeds
    7163|10|23|Linfrön|Leinsamen|Flax seeds
    7164|10|23|Chiafrön|Chiasamen|Chia seeds
    7165|10|23|Vallmofrön|Mohn|Poppy seeds
    7166|10|23|Pinjenötter|Pinienkerne|Pine nuts
    7167|10|23|Lönnsirap|Ahornsirup|Maple syrup
    7168|10|23|Äppelmos|Apfelmus|Apple sauce
    7169|10|23|Apelsinmarmelad|Orangenmarmelade|Orange marmalade
    7170|10|23|Hjortronsylt|Moltebeerkonfitüre|Cloudberry jam
    7171|10|23|Tahini|Tahini|Tahini
    7172|10|23|Mandelmassa|Mandelrohmasse|Almond paste
    7173|10|23|Marsipan|Marzipan|Marzipan
    7174|10|23|Bakchoklad|Backschokolade|Baking chocolate
    7175|10|23|Strössel|Zuckerstreusel|Sprinkles
    7176|10|23|Kokosolja|Kokosöl|Coconut oil
    7177|10|23|Sesamolja|Sesamöl|Sesame oil
    7178|10|23|Jordnötsolja|Erdnussöl|Peanut oil
    7179|10|23|Äppelcidervinäger|Apfelessig|Apple cider vinegar
    7180|10|23|Risvinäger|Reisessig|Rice vinegar
    7181|10|23|Ättika|Essigessenz|Spirit vinegar
    7182|10|23|Fiskbuljong|Fischbrühe|Fish stock
    7183|10|23|Köttbuljong|Fleischbrühe|Beef stock
    7184|10|23|Lagerblad|Lorbeerblätter|Bay leaves
    7185|10|23|Kryddpeppar|Piment|Allspice
    7186|10|23|Enbär|Wacholderbeeren|Juniper berries
    7187|10|23|Senapsfrön|Senfkörner|Mustard seeds
    7188|10|23|Fänkålsfrön|Fenchelsamen|Fennel seeds
    7189|10|23|Chiliflakes|Chiliflocken|Chili flakes
    7190|10|23|Garam masala|Garam Masala|Garam masala
    7191|10|23|Örtsalt|Kräutersalz|Herb salt
    7192|10|23|Grillkrydda|Grillgewürz|Barbecue seasoning
    7193|10|23|Ostronsås|Austernsauce|Oyster sauce
    7194|10|23|Fisksås|Fischsauce|Fish sauce
    7195|10|23|Hoisinsås|Hoisinsauce|Hoisin sauce
    7196|10|23|Chilisås|Chilisauce|Chili sauce
    7197|10|23|Sweet chilisås|Süße Chilisauce|Sweet chili sauce
    7198|10|23|Barbecuesås|Barbecuesauce|Barbecue sauce
    7199|10|23|Bearnaisesås|Sauce béarnaise|Béarnaise sauce
    7200|10|23|Hollandaisesås|Sauce hollandaise|Hollandaise sauce
    7201|10|23|Brunsås|Braune Sauce|Brown gravy
    7202|10|23|Dijonsenap|Dijonsenf|Dijon mustard
    7203|10|23|Currypasta|Currypaste|Curry paste
    7204|10|23|Miso|Miso|Miso
    7205|10|23|Sambal oelek|Sambal Oelek|Sambal oelek
    7206|10|23|Harissa|Harissa|Harissa
    7207|10|23|Gochujang|Gochujang|Gochujang
    7208|10|23|Kapris|Kapern|Capers
    7209|10|23|Soltorkade tomater|Getrocknete Tomaten|Sun-dried tomatoes
    7210|10|23|Inlagda rödbetor|Eingelegte Rote Bete|Pickled beetroot
    7211|10|23|Surkål|Sauerkraut|Sauerkraut
    7212|10|23|Kimchi|Kimchi|Kimchi
    7213|10|23|Bambuskott|Bambussprossen|Bamboo shoots
    7214|10|23|Vattenkastanjer|Wasserkastanien|Water chestnuts
    7215|10|23|Kokosgrädde|Kokoscreme|Coconut cream
    7216|10|23|Kondenserad mjölk|Kondensmilch|Condensed milk
    7217|10|23|Ravioli|Ravioli|Ravioli
    7218|10|23|Tortellini|Tortellini|Tortellini
    7219|10|23|Gnocchi|Gnocchi|Gnocchi
    7220|10|23|Risnudlar|Reisnudeln|Rice noodles
    7221|10|23|Udon-nudlar|Udon-Nudeln|Udon noodles
    7222|10|23|Sobanudlar|Soba-Nudeln|Soba noodles
    7223|10|23|Snabbnudlar|Instantnudeln|Instant noodles
    7224|10|23|Rispapper|Reispapier|Rice paper
    7225|10|23|Noriark|Noriblätter|Nori sheets
    7226|10|23|Panko|Panko|Panko breadcrumbs
    7227|10|23|Glutenfritt mjöl|Glutenfreies Mehl|Gluten-free flour
    7228|10|23|Glutenfria havregryn|Glutenfreie Haferflocken|Gluten-free oats
    7229|10|23|Välling|Getreidemilchbrei|Milk cereal drink
    7230|10|23|Barngröt|Babybrei|Baby porridge
    7231|10|23|Modersmjölksersättning|Säuglingsmilchnahrung|Infant formula
    7232|10|24|Falafel|Falafel|Falafel
    7233|10|24|Vårrullar|Frühlingsrollen|Spring rolls
    7234|10|24|Pytt i panna|Schwedische Kartoffel-Fleisch-Pfanne|Swedish hash
    7235|10|24|Kroketter|Kroketten|Potato croquettes
    7236|10|24|Potatisklyftor|Kartoffelspalten|Potato wedges
    7237|10|24|Raggmunk|Kartoffelpfannkuchen|Potato pancakes
    7238|10|24|Pannkakor|Pfannkuchen|Pancakes
    7239|10|24|Våfflor|Waffeln|Waffles
    7240|10|24|Frysta edamamebönor|Tiefgekühlte Edamame|Frozen edamame
    7241|10|24|Isbitar|Eiswürfel|Ice cubes
    7242|10|24|Glasspinnar|Eis am Stiel|Ice lollies
    7243|10|42|Tomatjuice|Tomatensaft|Tomato juice
    7244|10|42|Tranbärsjuice|Cranberrysaft|Cranberry juice
    7245|10|42|Druvjuice|Traubensaft|Grape juice
    7246|10|42|Kokosvatten|Kokoswasser|Coconut water
    7247|10|42|Iste|Eistee|Iced tea
    7248|10|42|Tonic|Tonic Water|Tonic water
    7249|10|42|Ingefärsläsk|Ingwerlimonade|Ginger ale
    7250|10|42|Julmust|Julmust|Swedish Christmas soda
    7251|10|42|Kombucha|Kombucha|Kombucha
    7252|10|42|Öl|Bier|Beer
    7253|10|42|Cider|Cider|Cider
    7254|10|42|Alkoholfritt vin|Alkoholfreier Wein|Alcohol-free wine
    7255|10|23|Snabbkaffe|Instantkaffee|Instant coffee
    7256|10|23|Koffeinfritt kaffe|Entkoffeinierter Kaffee|Decaffeinated coffee
    7257|10|23|Kaffebönor|Kaffeebohnen|Coffee beans
    7258|10|23|Kaffekapslar|Kaffeekapseln|Coffee capsules
    7259|10|43|Ostbågar|Käseflips|Cheese puffs
    7260|10|43|Linschips|Linsenchips|Lentil chips
    7261|10|43|Majskakor|Maiswaffeln|Corn cakes
    7262|10|43|Chokladkex|Schokoladenkekse|Chocolate biscuits
    7263|10|43|Smörkex|Butterkekse|Butter biscuits
    7264|10|43|Digestivekex|Vollkornkekse|Digestive biscuits
    7265|10|43|Maränger|Baisers|Meringues
    7266|10|43|Fudge|Fudge|Fudge
    7267|10|43|Kola|Karamellbonbons|Toffees
    7268|10|43|Halstabletter|Halsbonbons|Throat lozenges
    7269|10|43|Müslibars|Müsliriegel|Cereal bars
    7270|10|43|Proteinbars|Proteinriegel|Protein bars
    7271|11|25|Våtservetter|Feuchttücher|Wet wipes
    7272|11|25|Bomullspinnar|Wattestäbchen|Cotton buds
    7273|11|25|Näsdukar|Taschentücher|Tissues
    7274|11|25|Läppbalsam|Lippenbalsam|Lip balm
    7275|11|25|Sminkborttagning|Make-up-Entferner|Makeup remover
    7276|11|25|Nagellackborttagning|Nagellackentferner|Nail polish remover
    7277|11|25|Nagelfil|Nagelfeile|Nail file
    7278|11|25|Nagelklippare|Nagelknipser|Nail clippers
    7279|11|25|Hårborste|Haarbürste|Hairbrush
    7280|11|25|Hårsnoddar|Haargummis|Hair ties
    7281|11|25|Hårspray|Haarspray|Hairspray
    7282|11|25|Hårgel|Haargel|Hair gel
    7283|11|25|Torrschampo|Trockenshampoo|Dry shampoo
    7284|11|25|Rakblad|Rasierklingen|Razor blades
    7285|11|25|Aftershave|Aftershave|Aftershave
    7286|11|25|Mellanrumsborstar|Interdentalbürsten|Interdental brushes
    7287|11|25|Tandprotesrengöring|Gebissreiniger|Denture cleaner
    7288|11|25|Trosskydd|Slipeinlagen|Panty liners
    7289|11|25|Menskopp|Menstruationstasse|Menstrual cup
    7290|11|25|Inkontinensskydd|Inkontinenzeinlagen|Incontinence pads
    7291|11|25|Badblöjor|Schwimmwindeln|Swim diapers
    7292|11|25|Babyolja|Babyöl|Baby oil
    7293|11|25|Zinksalva|Zinksalbe|Zinc ointment
    7294|11|25|Napp|Schnuller|Pacifier
    7295|11|25|Nappflaska|Babyflasche|Baby bottle
    7296|11|25|Plåster|Pflaster|Adhesive bandages
    7297|11|25|Sårtvätt|Wundreinigung|Wound cleanser
    7298|11|25|Kompress|Wundkompresse|Wound dressing
    7299|11|25|Bandage|Verband|Bandage
    7300|11|25|Handsprit|Handdesinfektionsmittel|Hand sanitizer
    7301|11|25|Koksaltlösning|Kochsalzlösung|Saline solution
    7302|11|25|Kontaktlinsvätska|Kontaktlinsenlösung|Contact lens solution
    7303|11|25|Kondomer|Kondome|Condoms
    7304|11|25|Graviditetstest|Schwangerschaftstest|Pregnancy test
    7305|12|26|Diskmaskinssalt|Spülmaschinensalz|Dishwasher salt
    7306|12|26|Spolglans|Klarspüler|Dishwasher rinse aid
    7307|12|26|Ugnsrengöring|Backofenreiniger|Oven cleaner
    7308|12|26|Avkalkningsmedel|Entkalker|Descaler
    7309|12|26|Fettlösare|Fettlöser|Degreaser
    7310|12|26|Fläckborttagning|Fleckenentferner|Stain remover
    7311|12|26|Galltvål|Gallseife|Gall soap
    7312|12|26|Såpa|Schmierseife|Soft soap cleaner
    7313|12|26|Möbelpolish|Möbelpolitur|Furniture polish
    7314|12|26|Gummihandskar|Gummihandschuhe|Rubber gloves
    7315|12|26|Stålull|Stahlwolle|Steel wool
    7316|12|26|Skursvamp|Scheuerschwamm|Scouring pad
    7317|12|26|Mikrofiberduk|Mikrofasertuch|Microfiber cloth
    7318|12|26|Mopp|Wischmopp|Mop
    7319|12|26|Dammvippa|Staubwedel|Duster
    7320|12|26|Dammsugarpåsar|Staubsaugerbeutel|Vacuum cleaner bags
    7321|12|26|Kaffefilter|Kaffeefilter|Coffee filters
    7322|12|26|Muffinsformar|Muffinförmchen|Muffin cases
    7323|12|26|Servetter|Servietten|Napkins
    7324|12|26|Avfallspåsar för mat|Biomüllbeutel|Food waste bags
    7325|12|26|Matlådor|Frischhaltedosen|Food storage containers
    7326|12|26|Frysetiketter|Gefrieretiketten|Freezer labels
    7327|12|26|Tandpetare|Zahnstocher|Toothpicks
    7328|12|26|Grillspett|Grillspieße|Skewers
    7329|12|26|Sugrör|Trinkhalme|Drinking straws
    7330|12|26|Engångstallrikar|Einwegteller|Disposable plates
    7331|12|26|Engångsmuggar|Einwegbecher|Disposable cups
    7332|12|26|Värmeljus|Teelichter|Tea lights
    7333|12|26|Stearinljus|Kerzen|Candles
    7334|12|26|Tändstickor|Streichhölzer|Matches
    7335|12|26|Tändare|Feuerzeug|Lighter
    7336|12|26|Batterier|Batterien|Batteries
    7337|12|26|Glödlampor|Glühbirnen|Light bulbs
    7338|12|26|Grillkol|Grillkohle|Barbecue charcoal
    7339|12|26|Tändkuber|Anzündwürfel|Firelighters
    7340|12|26|Hundmat|Hundefutter|Dog food
    7341|12|26|Kattmat|Katzenfutter|Cat food
    7342|12|26|Hundgodis|Hundeleckerlis|Dog treats
    7343|12|26|Kattgodis|Katzenleckerlis|Cat treats
    7344|12|26|Kattsand|Katzenstreu|Cat litter
    7345|12|26|Hundbajspåsar|Hundekotbeutel|Dog waste bags
    7346|12|26|Fågelfrön|Vogelfutter|Bird seed
    7347|12|26|Blomjord|Blumenerde|Potting soil
    7348|12|26|Växtnäring|Pflanzendünger|Plant food
    7400|10|24|Laktosfri glass|Laktosefreies Eis|Lactose-free ice cream
    7401|10|24|Vegansk glass|Veganes Eis|Vegan ice cream
    7402|10|23|Fullkornspasta|Vollkornnudeln|Wholegrain pasta
    7403|10|23|Glutenfri pasta|Glutenfreie Nudeln|Gluten-free pasta
    7500|11|25|Mascara|Mascara|Mascara
    7501|11|25|Läppstift|Lippenstift|Lipstick
    7502|11|25|Läppglans|Lipgloss|Lip gloss
    7503|11|25|Foundation|Foundation|Foundation
    7504|11|25|Concealer|Concealer|Concealer
    7505|11|25|Ansiktspuder|Gesichtspuder|Face powder
    7506|11|25|Rouge|Rouge|Blush
    7507|11|25|Ögonskugga|Lidschatten|Eyeshadow
    7508|11|25|Kajalpenna|Kajalstift|Eyeliner pencil
    7509|11|25|Ögonbrynspenna|Augenbrauenstift|Eyebrow pencil
    7510|11|25|Nagellack|Nagellack|Nail polish
    7511|11|25|Sminkborstar|Make-up-Pinsel|Makeup brushes
    7512|11|25|Sminksvamp|Make-up-Schwamm|Makeup sponge
    7513|11|25|Ögonfransböjare|Wimpernzange|Eyelash curler
    7514|11|25|Pincett|Pinzette|Tweezers
    7515|11|25|Kosmetikspegel|Kosmetikspiegel|Makeup mirror
    7516|11|25|Micellärvatten|Mizellenwasser|Micellar water
    7517|11|25|Ansiktsserum|Gesichtsserum|Face serum
    7518|11|25|Ögonkräm|Augencreme|Eye cream
    7519|11|25|Kroppslotion|Körperlotion|Body lotion
    7520|11|25|Kroppsskrubb|Körperpeeling|Body scrub
    7521|11|25|Duscholja|Duschöl|Shower oil
    7522|11|25|Badsalt|Badesalz|Bath salts
    7523|11|25|After sun|After-Sun-Lotion|After-sun lotion
    7524|11|25|Brun utan sol|Selbstbräuner|Self-tanner
    7525|11|25|Vaselin|Vaseline|Petroleum jelly
    7526|11|25|Fotfil|Fußfeile|Foot file
    7527|11|25|Pimpsten|Bimsstein|Pumice stone
    7528|11|25|Fotbadssalt|Fußbadesalz|Foot soak salts
    7529|11|25|Hårfärg|Haarfarbe|Hair dye
    7530|11|25|Hårmousse|Haarschaum|Hair mousse
    7531|11|25|Hårvax|Haarwachs|Hair wax
    7532|11|25|Värmeskyddsspray|Hitzeschutzspray|Heat protection spray
    7533|11|25|Kam|Kamm|Comb
    7534|11|25|Hårklämmor|Haarspangen|Hair clips
    7535|11|25|Hårnålar|Haarnadeln|Hair pins
    7536|11|25|Duschmössa|Duschhaube|Shower cap
    7537|11|25|Skäggolja|Bartöl|Beard oil
    7538|11|25|Rakskum|Rasierschaum|Shaving foam
    7539|11|25|Hårborttagningskräm|Enthaarungscreme|Hair removal cream
    7540|11|25|Vaxremsor|Wachsstreifen|Wax strips
    7541|11|25|Elektrisk tandborste|Elektrische Zahnbürste|Electric toothbrush
    7542|11|25|Borsthuvuden till eltandborste|Ersatzbürstenköpfe|Replacement toothbrush heads
    7543|11|25|Barntandkräm|Kinderzahnpasta|Children's toothpaste
    7544|11|25|Barntandborste|Kinderzahnbürste|Children's toothbrush
    7545|11|25|Tungskrapa|Zungenschaber|Tongue scraper
    7546|11|25|Tandtrådsbyglar|Zahnseidesticks|Floss picks
    7547|11|25|Protesfixativ|Prothesenhaftcreme|Denture adhesive
    7548|11|25|Babyservetter|Babyfeuchttücher|Baby wipes
    7549|11|25|Babyschampo|Babyshampoo|Baby shampoo
    7550|11|25|Babytvål|Babyseife|Baby soap
    7551|11|25|Babykräm|Babycreme|Baby cream
    7552|11|25|Amningsinlägg|Stilleinlagen|Nursing pads
    7553|11|25|Bröstmjölkspåsar|Muttermilchbeutel|Breast milk storage bags
    7554|11|25|Flaskborste|Flaschenbürste|Bottle brush
    7555|11|25|Dinappar|Flaschensauger|Baby bottle teats
    7556|11|25|Bitring|Beißring|Teething ring
    7557|11|25|Haklapp|Lätzchen|Bib
    7558|11|25|Skötunderlägg|Wickelunterlagen|Changing pads
    7559|11|25|Öronproppar|Ohrstöpsel|Earplugs
    7560|11|25|Febertermometer|Fieberthermometer|Digital thermometer
    7561|11|25|Första hjälpen-kit|Erste-Hilfe-Set|First aid kit
    7562|11|25|Skavsårsplåster|Blasenpflaster|Blister plasters
    7563|11|25|Sårtejp|Wundpflasterstreifen|Wound closure strips
    7564|11|25|Förbandstejp|Heftpflasterrolle|Medical tape
    7565|11|25|Elastisk binda|Elastische Binde|Elastic bandage
    7566|11|25|Kylpåse|Kältekompresse|Cold pack
    7567|11|25|Värmeplåster|Wärmepflaster|Heat patches
    7568|11|25|Fästingplockare|Zeckenentferner|Tick remover
    7569|11|25|Insektsmedel|Insektenschutzmittel|Insect repellent
    7570|11|25|Ögondroppar|Augentropfen|Eye drops
    7571|11|25|Nässpray|Nasenspray|Nasal spray
    7572|11|25|Vätskeersättning|Elektrolytpulver|Oral rehydration salts
    7573|11|25|Multivitaminer|Multivitamine|Multivitamins
    7574|11|25|D-vitamin|Vitamin D|Vitamin D
    7575|11|25|C-vitamin|Vitamin C|Vitamin C
    7576|11|25|Magnesiumtabletter|Magnesiumtabletten|Magnesium tablets
    7577|11|25|Glidmedel|Gleitgel|Personal lubricant
    7578|11|25|Ägglossningstest|Ovulationstest|Ovulation test
    7579|11|25|Munskydd|Medizinische Masken|Medical face masks
    7580|11|25|Kontaktlinsfodral|Kontaktlinsenbehälter|Contact lens case
    7581|11|25|Glasögonservetter|Brillenputztücher|Lens cleaning wipes
    7582|11|25|Läsglasögon|Lesebrille|Reading glasses
    7583|11|25|Reseflaskor|Reisefläschchen|Travel toiletry bottles
    7584|11|25|Necessär|Kulturbeutel|Toiletry bag
    7585|12|26|Tvättmaskinsrengöring|Waschmaschinenreiniger|Washing machine cleaner
    7586|12|26|Diskmaskinsrengöring|Spülmaschinenreiniger|Dishwasher cleaner
    7587|12|26|Avloppsrensare|Abflussreiniger|Drain cleaner
    7588|12|26|Toalettblock|WC-Duftstein|Toilet rim block
    7589|12|26|Luftfräschare|Lufterfrischer|Air freshener
    7590|12|26|Textilspray|Textilerfrischer|Fabric freshener
    7591|12|26|Färgfångarark|Farbfangtücher|Color catcher sheets
    7592|12|26|Tvättpåsar|Wäschenetze|Laundry mesh bags
    7593|12|26|Klädnypor|Wäscheklammern|Clothes pegs
    7594|12|26|Klädvårdsrulle|Fusselrolle|Lint roller
    7595|12|26|Skokräm|Schuhcreme|Shoe polish
    7596|12|26|Impregneringsspray|Imprägnierspray|Waterproofing spray
    7597|12|26|Skosnören|Schnürsenkel|Shoelaces
    7598|12|26|Skoinlägg|Schuheinlagen|Shoe insoles
    7599|12|26|Sopborste|Besen|Broom
    7600|12|26|Sopskyffel|Kehrschaufel|Dustpan
    7601|12|26|Hink|Eimer|Bucket
    7602|12|26|Toalettborste|Toilettenbürste|Toilet brush
    7603|12|26|Duschskrapa|Duschabzieher|Shower squeegee
    7604|12|26|Tvättsvamp|Badeschwamm|Bath sponge
    7605|12|26|Engångshandskar|Einweghandschuhe|Disposable gloves
    7606|12|26|Återförslutningsbara påsar|Druckverschlussbeutel|Resealable bags
    7607|12|26|Påsklämmor|Beutelclips|Bag clips
    7608|12|26|Smörgåspåsar|Butterbrotbeutel|Sandwich bags
    7609|12|26|Bakformar|Backformen|Baking tins
    7610|12|26|Engångsbestick|Einwegbesteck|Disposable cutlery
    7611|12|26|Flasköppnare|Flaschenöffner|Bottle opener
    7612|12|26|Konservöppnare|Dosenöffner|Can opener
    7613|12|26|Korkskruv|Korkenzieher|Corkscrew
    7614|12|26|Diskhandduk|Geschirrtuch|Tea towel
    7615|12|26|Vattenflaska|Trinkflasche|Reusable water bottle
    7616|12|26|Termosmugg|Thermobecher|Travel mug
    7617|12|26|Shoppingkasse|Einkaufstasche|Shopping bag
    7618|12|26|Presentpapper|Geschenkpapier|Wrapping paper
    7619|12|26|Presentpåse|Geschenktüte|Gift bag
    7620|12|26|Presentband|Geschenkband|Gift ribbon
    7621|12|26|Tejp|Klebeband|Adhesive tape
    7622|12|26|Packtejp|Paketklebeband|Packing tape
    7623|12|26|Limstift|Klebestift|Glue stick
    7624|12|26|Snabblim|Sekundenkleber|Super glue
    7625|12|26|Sax|Schere|Scissors
    7626|12|26|Kulspetspennor|Kugelschreiber|Ballpoint pens
    7627|12|26|Blyertspennor|Bleistifte|Pencils
    7628|12|26|Suddgummi|Radiergummi|Eraser
    7629|12|26|Pennvässare|Anspitzer|Pencil sharpener
    7630|12|26|Anteckningsbok|Notizbuch|Notebook
    7631|12|26|Anteckningsblock|Notizblock|Notepad
    7632|12|26|Kuvert|Briefumschläge|Envelopes
    7633|12|26|Frimärken|Briefmarken|Postage stamps
    7634|12|26|Skrivarpapper|Druckerpapier|Printer paper
    7635|12|26|Märkpennor|Permanentmarker|Permanent markers
    7636|12|26|Överstrykningspennor|Textmarker|Highlighters
    7637|12|26|Gem|Büroklammern|Paper clips
    7638|12|26|Häftklamrar|Heftklammern|Staples
    7639|12|26|Gummiband|Gummibänder|Rubber bands
    7640|12|26|Säkerhetsnålar|Sicherheitsnadeln|Safety pins
    7641|12|26|Sytråd|Nähgarn|Sewing thread
    7642|12|26|Synålar|Nähnadeln|Sewing needles
    7643|12|26|USB-kabel|USB-Kabel|USB cable
    7644|12|26|Mobilladdare|Handyladegerät|Phone charger
    7645|12|26|Powerbank|Powerbank|Power bank
    7646|12|26|Hörlurar|Kopfhörer|Headphones
    7647|12|26|Ficklampa|Taschenlampe|Flashlight
    7648|12|26|Reseadapter|Reiseadapter|Travel adapter
    7649|12|26|Paraply|Regenschirm|Umbrella
    7650|12|26|Hundschampo|Hundeshampoo|Dog shampoo
    7651|12|26|Tuggben|Kauknochen|Dog chews
    7652|12|26|Hundleksak|Hundespielzeug|Dog toy
    7653|12|26|Kattleksak|Katzenspielzeug|Cat toy
    7654|12|26|Husdjursmatskål|Futternapf|Pet food bowl
    7655|12|26|Smådjursströ|Kleintierstreu|Small animal bedding
    7656|12|26|Hö för smådjur|Kleintierheu|Small animal hay
    7657|12|26|Fiskfoder|Fischfutter|Fish food
    7658|12|26|Flugpapper|Fliegenfänger|Fly paper
    7659|12|26|Malfällor|Mottenfallen|Moth traps
    7660|13|27|Strumpbyxor|Strumpfhosen|Tights
    7661|13|27|Underkläder|Unterwäsche|Underwear
    7662|13|27|Handskar|Handschuhe|Gloves
    7663|13|27|Regnponcho|Regenponcho|Rain poncho
    7664|14|27|Tidning|Zeitung|Newspaper
    7665|14|27|Tidskrift|Zeitschrift|Magazine
    7666|14|27|Gratulationskort|Glückwunschkarte|Greeting card
    7667|14|27|Spelkort|Spielkarten|Playing cards
    7668|14|27|Ballonger|Luftballons|Balloons
    7669|14|27|Födelsedagsljus|Geburtstagskerzen|Birthday candles
    7670|14|27|Färgpennor|Buntstifte|Colored pencils
    7671|14|27|Målarbok|Malbuch|Coloring book
    7672|10|22|Färdig smörgås|Belegtes Sandwich|Ready-made sandwich
    7673|10|22|Färdig sallad|Fertigsalat|Prepared salad
    7674|10|22|Färdig wrap|Belegter Wrap|Ready-made wrap
    7675|10|22|Sushi|Sushi|Sushi
    7676|10|42|Iskaffe|Eiskaffee|Iced coffee
    7677|10|42|Sportdryck|Sportgetränk|Sports drink
    7678|10|42|Chokladmjölk|Schokoladenmilch|Chocolate milk
    """

    // Inclusive old-ID range | canonical ID. Covers every former 2000–6999 seed.
    private static let legacyRanges = """
    2000|2003|2000
    2004|2007|7402
    2008|2011|2000
    2012|2015|7403
    2016|2019|2016
    2020|2023|7402
    2024|2027|2016
    2028|2031|7403
    2032|2035|2032
    2036|2039|7402
    2040|2043|2032
    2044|2047|7403
    2048|2051|2048
    2052|2055|7402
    2056|2059|2048
    2060|2063|7403
    2064|2067|2064
    2068|2071|7402
    2072|2075|2064
    2076|2079|7403
    2080|2083|2080
    2084|2087|7402
    2088|2091|2080
    2092|2095|7403
    2096|2099|2096
    2100|2103|7402
    2104|2107|2096
    2108|2111|7403
    2112|2115|2112
    2116|2119|7402
    2120|2123|2112
    2124|2127|7403
    2128|2131|2128
    2132|2135|7402
    2136|2139|2128
    2140|2143|7403
    2144|2147|1184
    2148|2151|7402
    2152|2155|1184
    2156|2159|7403
    2160|2167|2160
    2168|2175|2168
    2176|2183|2176
    2184|2191|2184
    2192|2199|2192
    2200|2207|2200
    2208|2215|2208
    2216|2223|2216
    2224|2231|2224
    2232|2239|2232
    2240|2263|1181
    2264|2271|1180
    2272|2279|1179
    2280|2287|2280
    2288|2295|2288
    2296|2303|2296
    2304|2311|2304
    2312|2319|2312
    2320|2327|1174
    2328|2335|1175
    2336|2343|2336
    2344|2351|2344
    2352|2359|2352
    2360|2367|2360
    2368|2375|1170
    2376|2383|1172
    2384|2391|1171
    2392|2399|1173
    2400|2407|2400
    2408|2415|2408
    2416|2423|2416
    2424|2431|2424
    2432|2439|2432
    2440|2447|2440
    2448|2455|2448
    2456|2463|2456
    2464|2471|2464
    2472|2479|2472
    2480|2487|1139
    2488|2495|2488
    2496|2503|1140
    2504|2511|2504
    2512|2519|2512
    2520|2527|2520
    2528|2535|2528
    2536|2543|2536
    2544|2551|2544
    2552|2559|2552
    2560|2567|1141
    2568|2575|2568
    2576|2583|2576
    2584|2591|2584
    2592|2599|2592
    2600|2607|2600
    2608|2615|2608
    2616|2623|2616
    2624|2631|2624
    2632|2639|2632
    2640|2647|1187
    2648|2655|2648
    2656|2663|1191
    2664|2671|2664
    2672|2679|2672
    2680|2687|1190
    2688|2695|2688
    2696|2703|2696
    2704|2711|2704
    2712|2719|2712
    2720|2727|1188
    2728|2735|2728
    2736|2743|2736
    2744|2751|2744
    2752|2759|2752
    2760|2767|1192
    2768|2775|1193
    2776|2783|2776
    2784|2791|2784
    2792|2799|2792
    2800|2815|1270
    2816|2831|1271
    2832|2847|1272
    2848|2863|1274
    2864|2879|1275
    2880|2895|2880
    2896|2911|2896
    2912|2927|2912
    2928|2943|1273
    2944|2959|2944
    2960|2967|1199
    2968|2975|2968
    2976|2983|1277
    2984|2991|2984
    2992|2999|2992
    3000|3007|3000
    3008|3015|3008
    3016|3023|3016
    3024|3031|3024
    3032|3039|3032
    3040|3047|3040
    3048|3055|3048
    3056|3063|3056
    3064|3071|3064
    3072|3079|3072
    3080|3087|3080
    3088|3103|1276
    3104|3111|3104
    3112|3119|3112
    3120|3135|1152
    3136|3151|3136
    3152|3167|3152
    3168|3183|3168
    3184|3199|3184
    3200|3215|3200
    3216|3231|3216
    3232|3247|3232
    3248|3263|3248
    3264|3279|3264
    3280|3287|3280
    3288|3291|7113
    3292|3295|3280
    3296|3303|3296
    3304|3307|7113
    3308|3311|3296
    3312|3319|3312
    3320|3323|7113
    3324|3327|3312
    3328|3335|3328
    3336|3339|7113
    3340|3343|3328
    3344|3351|3344
    3352|3355|7113
    3356|3359|3344
    3360|3367|3360
    3368|3371|7113
    3372|3375|3360
    3376|3383|1092
    3384|3387|7113
    3388|3391|1092
    3392|3399|3392
    3400|3403|7113
    3404|3407|3392
    3408|3415|3408
    3416|3419|7113
    3420|3423|3408
    3424|3431|3424
    3432|3435|7113
    3436|3439|3424
    3440|3443|3440
    3444|3455|7401
    3456|3459|3456
    3460|3471|7401
    3472|3475|3472
    3476|3487|7401
    3488|3491|3488
    3492|3503|7401
    3504|3507|3504
    3508|3519|7401
    3520|3523|3520
    3524|3535|7401
    3536|3539|3536
    3540|3551|7401
    3552|3555|3552
    3556|3567|7401
    3568|3571|3568
    3572|3583|7401
    3584|3587|3584
    3588|3599|7401
    3600|3607|1201
    3608|3611|1213
    3612|3615|1207
    3616|3623|3616
    3624|3627|1213
    3628|3631|1207
    3632|3639|3632
    3640|3643|1213
    3644|3647|1207
    3648|3655|3648
    3656|3659|1213
    3660|3663|1207
    3664|3671|3664
    3672|3675|1213
    3676|3679|1207
    3680|3687|3680
    3688|3691|1213
    3692|3695|1207
    3696|3703|3696
    3704|3707|1213
    3708|3711|1207
    3712|3719|3712
    3720|3723|1213
    3724|3727|1207
    3728|3735|3728
    3736|3739|1213
    3740|3743|1207
    3744|3751|3744
    3752|3755|1213
    3756|3759|1207
    3760|3767|3760
    3768|3775|3768
    3776|3783|3776
    3784|3791|3784
    3792|3799|3792
    3800|3807|3800
    3808|3815|3808
    3816|3823|3816
    3824|3831|3824
    3832|3839|3832
    3840|3847|3840
    3848|3855|3848
    3856|3863|3856
    3864|3871|3864
    3872|3879|3872
    3880|3887|3880
    3888|3895|3888
    3896|3903|3896
    3904|3911|3904
    3912|3919|3912
    3920|3927|7257
    3928|3935|108
    3936|3943|7257
    3944|3951|108
    3952|3959|7257
    3960|3967|108
    3968|3975|7257
    3976|3983|108
    3984|3991|7257
    3992|3999|108
    4000|4007|7257
    4008|4015|108
    4016|4023|7257
    4024|4031|108
    4032|4039|7257
    4040|4047|108
    4048|4055|7257
    4056|4063|108
    4064|4071|7257
    4072|4079|108
    4080|4087|4080
    4088|4095|4088
    4096|4103|4096
    4104|4111|1085
    4112|4119|4112
    4120|4127|4120
    4128|4135|4096
    4136|4143|4136
    4144|4151|4144
    4152|4159|4152
    4160|4167|4160
    4168|4175|7123
    4176|4183|4176
    4184|4191|4184
    4192|4199|4192
    4200|4207|4200
    4208|4215|4208
    4216|4223|4216
    4224|4231|4224
    4232|4239|4232
    4240|4255|1095
    4256|4271|4256
    4272|4287|1098
    4288|4303|4288
    4304|4319|4304
    4320|4335|1104
    4336|4351|1105
    4352|4367|1103
    4368|4383|4368
    4384|4399|1118
    4400|4403|1120
    4404|4407|4404
    4408|4411|1121
    4412|4415|4412
    4416|4419|1122
    4420|4423|4420
    4424|4427|4424
    4428|4431|4428
    4432|4435|4432
    4436|4439|4436
    4440|4443|4440
    4444|4447|4444
    4448|4451|4448
    4452|4455|4452
    4456|4459|4456
    4460|4463|4460
    4464|4467|4464
    4468|4471|4468
    4472|4475|4472
    4476|4479|4476
    4480|4483|4480
    4484|4487|4484
    4488|4491|4488
    4492|4495|4492
    4496|4499|4496
    4500|4503|4500
    4504|4507|4504
    4508|4511|4508
    4512|4515|4512
    4516|4519|4516
    4520|4523|4520
    4524|4527|4524
    4528|4531|4528
    4532|4535|4532
    4536|4539|4536
    4540|4543|4540
    4544|4547|4544
    4548|4551|4548
    4552|4555|4552
    4556|4559|4556
    4560|4563|1028
    4564|4567|1216
    4568|4571|1029
    4572|4575|4572
    4576|4579|4576
    4580|4583|4580
    4584|4587|1033
    4588|4591|1217
    4592|4595|1032
    4596|4599|4596
    4600|4603|4600
    4604|4607|4604
    4608|4611|4608
    4612|4615|4612
    4616|4619|4616
    4620|4623|4620
    4624|4627|4624
    4628|4631|1215
    4632|4635|4632
    4636|4639|4636
    4640|4643|1022
    4644|4647|4644
    4648|4651|7016
    4652|4655|4652
    4656|4659|1039
    4660|4663|4660
    4664|4667|7000
    4668|4671|4668
    4672|4675|1026
    4676|4679|4676
    4680|4683|1021
    4684|4687|4684
    4688|4691|1038
    4692|4695|4692
    4696|4699|1043
    4700|4703|4700
    4704|4707|1036
    4708|4711|4708
    4712|4715|1023
    4716|4719|4716
    4720|4723|1007
    4724|4727|1220
    4728|4731|1009
    4732|4735|1218
    4736|4739|1008
    4740|4743|1219
    4744|4747|1010
    4748|4751|4748
    4752|4755|4752
    4756|4759|4756
    4760|4763|4760
    4764|4767|4764
    4768|4771|4768
    4772|4775|4772
    4776|4779|7044
    4780|4783|4780
    4784|4787|4784
    4788|4791|4788
    4792|4795|4792
    4796|4799|4796
    4800|4803|1011
    4804|4807|1221
    4808|4811|1012
    4812|4815|4812
    4816|4819|1014
    4820|4823|4820
    4824|4827|7043
    4828|4831|4828
    4832|4835|1016
    4836|4839|4836
    4840|4843|4840
    4844|4847|4844
    4848|4851|103
    4852|4855|4852
    4856|4859|104
    4860|4863|4860
    4864|4867|1000
    4868|4871|4868
    4872|4875|7042
    4876|4879|4876
    4880|4895|1050
    4896|4911|4896
    4912|4927|4912
    4928|4943|4928
    4944|4959|1052
    4960|4975|1051
    4976|4991|4976
    4992|5007|4992
    5008|5023|5008
    5024|5039|5024
    5040|5055|5040
    5056|5071|5056
    5072|5087|5072
    5088|5103|5088
    5104|5119|5104
    5120|5135|5120
    5136|5151|5136
    5152|5167|5152
    5168|5183|5168
    5184|5199|5184
    5200|5215|5200
    5216|5231|5216
    5232|5247|5232
    5248|5263|5248
    5264|5279|5264
    5280|5295|5280
    5296|5311|5296
    5312|5327|5312
    5328|5343|5328
    5344|5359|5344
    5360|5367|5360
    5368|5375|5368
    5376|5383|5376
    5384|5391|5384
    5392|5399|5392
    5400|5407|5400
    5408|5415|5408
    5416|5423|5416
    5424|5431|5424
    5432|5439|5432
    5440|5447|5440
    5448|5455|5448
    5456|5463|5456
    5464|5471|5464
    5472|5479|5472
    5480|5487|5480
    5488|5495|5488
    5496|5503|5496
    5504|5511|5504
    5512|5519|5512
    5520|5527|5520
    5528|5535|5528
    5536|5543|5536
    5544|5551|5544
    5552|5559|5552
    5560|5567|5560
    5568|5575|5568
    5576|5583|5576
    5584|5591|5584
    5592|5599|5592
    5600|5607|5600
    5608|5615|5608
    5616|5623|5616
    5624|5631|5624
    5632|5639|5632
    5640|5647|5640
    5648|5655|5648
    5656|5663|5656
    5664|5671|5664
    5672|5679|5672
    5680|5695|1137
    5696|5711|5696
    5712|5727|5712
    5728|5743|5728
    5744|5759|1136
    5760|5775|5760
    5776|5791|5776
    5792|5807|5792
    5808|5823|5808
    5824|5839|5824
    5840|5847|5840
    5848|5855|5848
    5856|5863|5856
    5864|5871|5864
    5872|5879|5872
    5880|5887|5880
    5888|5895|5888
    5896|5903|5896
    5904|5911|5904
    5912|5919|5912
    5920|5927|5920
    5928|5935|5928
    5936|5943|5936
    5944|5951|5944
    5952|5959|5952
    5960|5967|5960
    5968|5975|5968
    5976|5983|5976
    5984|5991|5984
    5992|5999|5992
    6000|6019|113
    6020|6039|1230
    6040|6059|6040
    6060|6079|6060
    6080|6099|6080
    6100|6139|1231
    6140|6159|1232
    6160|6179|1239
    6180|6199|6180
    6200|6219|6200
    6220|6239|6220
    6240|6259|6240
    6260|6279|6260
    6280|6299|6280
    6300|6339|6300
    6340|6359|6340
    6360|6399|1239
    6400|6499|1240
    6500|6599|112
    6600|6699|1242
    6700|6799|1244
    6800|6819|1257
    6820|6839|6820
    6840|6859|6840
    6860|6879|1259
    6880|6899|114
    6900|6979|1246
    6980|6999|1247
    """
}
