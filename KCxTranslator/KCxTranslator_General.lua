local generalDictionary = {
    -- greetings / chat
    ["hello"] = "hola", ["hola"] = "hello",
    ["hi"] = "hola", ["hey"] = "oye",
    ["good morning"] = "buenos dias", ["buenos dias"] = "good morning",
    ["good night"] = "buenas noches", ["buenas noches"] = "good night",
    ["please"] = "por favor", ["por favor"] = "please",
    ["thanks"] = "gracias", ["gracias"] = "thanks",
    ["thank you"] = "gracias", ["you are welcome"] = "de nada", ["de nada"] = "you are welcome",
    ["sorry"] = "perdon", ["perdon"] = "sorry",
    ["yes"] = "si", ["si"] = "yes", ["no"] = "no",
    -- pronouns / basics
    ["i"] = "yo", ["yo"] = "i", ["you"] = "tu", ["tu"] = "you",
    ["we"] = "nosotros", ["nosotros"] = "we", ["they"] = "ellos", ["ellos"] = "they",
    ["my"] = "mi", ["mi"] = "my", ["your"] = "tu", ["our"] = "nuestro",
    ["am"] = "estoy", ["are"] = "estas", ["is"] = "es",
    -- questions
    ["what"] = "que", ["que"] = "what", ["where"] = "donde", ["donde"] = "where",
    ["when"] = "cuando", ["cuando"] = "when", ["why"] = "porque", ["porque"] = "why",
    ["who"] = "quien", ["quien"] = "who", ["how"] = "como", ["como"] = "how",
    -- prepositions/connectors
    ["with"] = "con", ["con"] = "with", ["without"] = "sin", ["sin"] = "without",
    ["for"] = "para", ["para"] = "for", ["from"] = "de", ["to"] = "a",
    ["in"] = "en", ["on"] = "en", ["at"] = "en", ["and"] = "y", ["y"] = "and",
    ["or"] = "o", ["but"] = "pero", ["because"] = "porque",
    -- time
    ["now"] = "ahora", ["ahora"] = "now", ["today"] = "hoy", ["hoy"] = "today",
    ["tomorrow"] = "manana", ["manana"] = "tomorrow", ["yesterday"] = "ayer", ["ayer"] = "yesterday",
    ["tonight"] = "esta noche", ["esta noche"] = "tonight",
    ["minute"] = "minuto", ["minuto"] = "minute", ["hour"] = "hora", ["hora"] = "hour",
    -- numbers
    ["one"] = "uno", ["uno"] = "one", ["two"] = "dos", ["dos"] = "two",
    ["three"] = "tres", ["tres"] = "three", ["four"] = "cuatro", ["cuatro"] = "four",
    ["five"] = "cinco", ["cinco"] = "five", ["ten"] = "diez", ["diez"] = "ten",
    -- colors
    ["red"] = "rojo", ["rojo"] = "red", ["blue"] = "azul", ["azul"] = "blue",
    ["green"] = "verde", ["verde"] = "green", ["black"] = "negro", ["negro"] = "black",
    ["white"] = "blanco", ["blanco"] = "white",
    -- family
    ["mother"] = "madre", ["madre"] = "mother", ["father"] = "padre", ["padre"] = "father",
    ["brother"] = "hermano", ["hermano"] = "brother", ["sister"] = "hermana", ["hermana"] = "sister",
    ["friend"] = "amigo", ["amigo"] = "friend",
    -- places
    ["house"] = "casa", ["casa"] = "house", ["city"] = "ciudad", ["ciudad"] = "city",
    ["town"] = "pueblo", ["pueblo"] = "town", ["school"] = "escuela", ["escuela"] = "school",
    -- food
    ["food"] = "comida", ["comida"] = "food", ["water"] = "agua", ["agua"] = "water",
    ["bread"] = "pan", ["pan"] = "bread", ["meat"] = "carne", ["carne"] = "meat",
    -- emotions/adjectives
    ["happy"] = "feliz", ["feliz"] = "happy", ["sad"] = "triste", ["triste"] = "sad",
    ["crazy"] = "loco", ["loco"] = "crazy", ["good"] = "bueno", ["bueno"] = "good",
    ["bad"] = "malo", ["malo"] = "bad", ["funny"] = "gracioso", ["gracioso"] = "funny",
    -- directions
    ["left"] = "izquierda", ["izquierda"] = "left",
    ["right"] = "derecha", ["derecha"] = "right",
    ["up"] = "arriba", ["arriba"] = "up", ["down"] = "abajo", ["abajo"] = "down",
    ["north"] = "norte", ["south"] = "sur", ["east"] = "este", ["west"] = "oeste",
    -- common phrases
    ["how are you"] = "como estas", ["como estas"] = "how are you",
    ["is"] = "esta", ["esta"] = "is",
    ["now"] = "ahora",
    ["food"] = "comida",
    ["for"] = "para",
    ["tonight"] = "esta noche", ["esta noche"] = "tonight",
    ["incoming"] = "entrando", ["entrando"] = "incoming",
    ["i need help"] = "necesito ayuda", ["necesito ayuda"] = "i need help",
    ["where is"] = "donde esta", ["donde esta"] = "where is",
    ["can you repeat please"] = "puedes repetir por favor",
    ["i am using a translator"] = "estoy usando un traductor",
}

KCxTranslator_RegisterGeneralDictionary(generalDictionary, "General")

-- Test examples (manual):
-- /kcxt hello my friend how are you
-- /kcxt i need food and water
-- /kcxt where is the house
-- /kcxt we are ready now
-- /kcxt necesito ayuda con esto
-- /kcxt donde esta mi amigo
-- /kcxt i am using a translator
-- /kcxt can you repeat please
