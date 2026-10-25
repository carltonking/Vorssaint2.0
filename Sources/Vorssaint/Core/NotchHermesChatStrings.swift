// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Hermes page's words: what the settings say, and what a conversation
/// that is starting, stopped or refused says for itself.
struct NotchHermesChatStrings {
    let title: String
    let description: String
    let enable: String
    let cliPath: String
    let cliPathPlaceholder: String
    let cliPathHint: String
    let requiresDynamicIsland: String
    let enableDynamicIsland: String
    let connecting: String
    let ready: String
    let placeholder: String
    let send: String
    let stop: String
    let clear: String
    let retry: String
    let emptyTitle: String
    let emptySubtitle: String
    let thinking: String
    let stopped: String
    let stoppedAtLimit: String
    let stoppedAtStepLimit: String
    let refusedByAgent: String
    let refusedCommand: String
    let refusedCommandFormat: String
    let notFoundFormat: String
    let unreachableFormat: String
    let you: String
    let copyMessage: String
    let editMessage: String
    let approvalTitle: String
    let allowOnce: String
    let allowSession: String
    let allowAlways: String
    let deny: String
    let approvalAllowed: String
    let approvalDenied: String
    let approvalExpired: String
    let reachedOut: String
    let reachedOutFormat: String

    func notFound(_ command: String) -> String { String(format: notFoundFormat, command) }

    func unreachable(_ reason: String) -> String { String(format: unreachableFormat, reason) }

    func refusedCommandLine(_ subject: String) -> String {
        String(format: refusedCommandFormat, subject)
    }

    /// The line over a message VERTUS sent unasked, naming the routine that
    /// wrote it when the hub said which.
    func reachedOut(_ routine: String?) -> String {
        guard let routine, !routine.isEmpty else { return reachedOut }
        return String(format: reachedOutFormat, routine)
    }
}

extension FeatureStrings {
    static func notchHermesChat(_ language: AppLanguage) -> NotchHermesChatStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NotchHermesChatStrings {
    static let enUS = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Talk to VERTUS, running on this Mac, from the island.",
        enable: "Show VERTUS in the island",
        cliPath: "VERTUS command",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Run with acp. VERTUS keeps running while this is on.",
        requiresDynamicIsland: "VERTUS needs the Dynamic Island.",
        enableDynamicIsland: "Turn On Dynamic Island",
        connecting: "Starting VERTUS…",
        ready: "Connected",
        placeholder: "Ask VERTUS…",
        send: "Send",
        stop: "Stop",
        clear: "Clear Conversation",
        retry: "Try Again",
        emptyTitle: "Ask VERTUS anything",
        emptySubtitle: "VERTUS runs here, with the models and tools you set up for it.",
        thinking: "Thinking",
        stopped: "Stopped.",
        stoppedAtLimit: "The reply reached its length limit.",
        stoppedAtStepLimit: "The reply reached its step limit.",
        refusedByAgent: "VERTUS declined this request.",
        refusedCommand: "VERTUS asked to run a tool. The island always answers no, so run it yourself in a terminal.",
        refusedCommandFormat: "VERTUS asked to run “%1$@”. The island always answers no, so run it yourself in a terminal.",
        notFoundFormat: "Nothing runs at “%1$@”. Set the VERTUS command in Settings.",
        unreachableFormat: "VERTUS stopped answering: %1$@",
        you: "You",
        copyMessage: "Copy",
        editMessage: "Edit",
        approvalTitle: "VERTUS needs your OK",
        allowOnce: "Allow Once",
        allowSession: "Allow for This Chat",
        allowAlways: "Always Allow",
        deny: "Deny",
        approvalAllowed: "Allowed.",
        approvalDenied: "Denied.",
        approvalExpired: "The request expired before an answer.",
        reachedOut: "VERTUS reached out",
        reachedOutFormat: "VERTUS reached out · %1$@"
    )

    static let ptBR = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Converse com o VERTUS, rodando neste Mac, a partir da ilha.",
        enable: "Mostrar o Chat VERTUS na ilha",
        cliPath: "Comando do VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Executado com acp. O VERTUS continua rodando enquanto isto estiver ativado.",
        requiresDynamicIsland: "O Chat VERTUS precisa da Dynamic Island.",
        enableDynamicIsland: "Ativar Dynamic Island",
        connecting: "Iniciando o VERTUS…",
        ready: "Conectado",
        placeholder: "Pergunte ao VERTUS…",
        send: "Enviar",
        stop: "Parar",
        clear: "Limpar conversa",
        retry: "Tentar de novo",
        emptyTitle: "Pergunte qualquer coisa ao VERTUS",
        emptySubtitle: "O VERTUS roda aqui, com os modelos e ferramentas que você configurou.",
        thinking: "Pensando",
        stopped: "Interrompido.",
        stoppedAtLimit: "A resposta atingiu o limite de tamanho.",
        stoppedAtStepLimit: "A resposta atingiu o limite de etapas.",
        refusedByAgent: "O VERTUS recusou este pedido.",
        refusedCommand: "O VERTUS pediu para executar uma ferramenta. A ilha sempre responde não, então execute você mesmo no terminal.",
        refusedCommandFormat: "O VERTUS pediu para executar “%1$@”. A ilha sempre responde não, então execute você mesmo no terminal.",
        notFoundFormat: "Nada é executado em “%1$@”. Defina o comando do VERTUS nos Ajustes.",
        unreachableFormat: "O VERTUS parou de responder: %1$@",
        you: "Você",
        copyMessage: "Copiar",
        editMessage: "Editar",
        approvalTitle: "O VERTUS precisa da sua permissão",
        allowOnce: "Permitir uma vez",
        allowSession: "Permitir nesta conversa",
        allowAlways: "Sempre permitir",
        deny: "Negar",
        approvalAllowed: "Permitido.",
        approvalDenied: "Negado.",
        approvalExpired: "O pedido expirou antes de uma resposta.",
        reachedOut: "O VERTUS entrou em contato",
        reachedOutFormat: "O VERTUS entrou em contato · %1$@"
    )

    static let es = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Habla con VERTUS, que se ejecuta en este Mac, desde la isla.",
        enable: "Mostrar el chat de VERTUS en la isla",
        cliPath: "Comando de VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Se ejecuta con acp. VERTUS sigue en marcha mientras esto esté activado.",
        requiresDynamicIsland: "El chat de VERTUS necesita la Dynamic Island.",
        enableDynamicIsland: "Activar Dynamic Island",
        connecting: "Iniciando VERTUS…",
        ready: "Conectado",
        placeholder: "Pregunta a VERTUS…",
        send: "Enviar",
        stop: "Detener",
        clear: "Borrar conversación",
        retry: "Reintentar",
        emptyTitle: "Pregúntale lo que quieras a VERTUS",
        emptySubtitle: "VERTUS se ejecuta aquí, con los modelos y las herramientas que hayas configurado.",
        thinking: "Pensando",
        stopped: "Detenido.",
        stoppedAtLimit: "La respuesta alcanzó su límite de longitud.",
        stoppedAtStepLimit: "La respuesta alcanzó su límite de pasos.",
        refusedByAgent: "VERTUS rechazó esta petición.",
        refusedCommand: "VERTUS pidió ejecutar una herramienta. La isla siempre responde que no, así que ejecútala tú en el terminal.",
        refusedCommandFormat: "VERTUS pidió ejecutar “%1$@”. La isla siempre responde que no, así que ejecútala tú en el terminal.",
        notFoundFormat: "No se ejecuta nada en “%1$@”. Define el comando de VERTUS en Ajustes.",
        unreachableFormat: "VERTUS dejó de responder: %1$@",
        you: "Tú",
        copyMessage: "Copiar",
        editMessage: "Editar",
        approvalTitle: "VERTUS necesita tu permiso",
        allowOnce: "Permitir una vez",
        allowSession: "Permitir en esta conversación",
        allowAlways: "Permitir siempre",
        deny: "Denegar",
        approvalAllowed: "Permitido.",
        approvalDenied: "Denegado.",
        approvalExpired: "La solicitud caducó antes de una respuesta.",
        reachedOut: "VERTUS te escribió",
        reachedOutFormat: "VERTUS te escribió · %1$@"
    )

    static let sk = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Rozprávajte sa s VERTUS, ktorý beží na tomto Macu, priamo z ostrova.",
        enable: "Zobraziť chat s VERTUS v ostrove",
        cliPath: "Príkaz VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Spúšťa sa s acp. VERTUS beží, kým je toto zapnuté.",
        requiresDynamicIsland: "Chat s VERTUS vyžaduje Dynamic Island.",
        enableDynamicIsland: "Zapnúť Dynamic Island",
        connecting: "Spúšťam VERTUS…",
        ready: "Pripojené",
        placeholder: "Opýtajte sa VERTUSa…",
        send: "Odoslať",
        stop: "Zastaviť",
        clear: "Vymazať konverzáciu",
        retry: "Skúsiť znova",
        emptyTitle: "Opýtajte sa VERTUSa na čokoľvek",
        emptySubtitle: "VERTUS beží tu, s modelmi a nástrojmi, ktoré ste mu nastavili.",
        thinking: "Premýšľa",
        stopped: "Zastavené.",
        stoppedAtLimit: "Odpoveď dosiahla limit dĺžky.",
        stoppedAtStepLimit: "Odpoveď dosiahla limit krokov.",
        refusedByAgent: "VERTUS túto požiadavku odmietol.",
        refusedCommand: "VERTUS požiadal o spustenie nástroja. Ostrov vždy odpovie nie, takže ho spustite sami v termináli.",
        refusedCommandFormat: "VERTUS požiadal o spustenie “%1$@”. Ostrov vždy odpovie nie, takže ho spustite sami v termináli.",
        notFoundFormat: "Na “%1$@” sa nič nespúšťa. Nastavte príkaz VERTUS v Nastaveniach.",
        unreachableFormat: "VERTUS prestal odpovedať: %1$@",
        you: "Vy",
        copyMessage: "Kopírovať",
        editMessage: "Upraviť",
        approvalTitle: "VERTUS potrebuje váš súhlas",
        allowOnce: "Povoliť raz",
        allowSession: "Povoliť v tomto chate",
        allowAlways: "Povoliť vždy",
        deny: "Zamietnuť",
        approvalAllowed: "Povolené.",
        approvalDenied: "Zamietnuté.",
        approvalExpired: "Žiadosť vypršala skôr, než prišla odpoveď.",
        reachedOut: "VERTUS sa ozval",
        reachedOutFormat: "VERTUS sa ozval · %1$@"
    )

    static let de = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Sprich mit VERTUS, der auf diesem Mac läuft, direkt aus der Insel.",
        enable: "VERTUS-Chat in der Insel anzeigen",
        cliPath: "VERTUS-Befehl",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Wird mit acp ausgeführt. VERTUS läuft weiter, solange dies aktiv ist.",
        requiresDynamicIsland: "Der VERTUS-Chat benötigt die Dynamic Island.",
        enableDynamicIsland: "Dynamic Island aktivieren",
        connecting: "VERTUS wird gestartet…",
        ready: "Verbunden",
        placeholder: "Frag VERTUS…",
        send: "Senden",
        stop: "Anhalten",
        clear: "Unterhaltung löschen",
        retry: "Erneut versuchen",
        emptyTitle: "Frag VERTUS alles",
        emptySubtitle: "VERTUS läuft hier, mit den Modellen und Werkzeugen, die du eingerichtet hast.",
        thinking: "Denkt nach",
        stopped: "Angehalten.",
        stoppedAtLimit: "Die Antwort hat ihr Längenlimit erreicht.",
        stoppedAtStepLimit: "Die Antwort hat ihr Schrittenlimit erreicht.",
        refusedByAgent: "VERTUS hat diese Anfrage abgelehnt.",
        refusedCommand: "VERTUS möchte ein Werkzeug ausführen. Die Insel antwortet immer mit Nein, führe es also selbst im Terminal aus.",
        refusedCommandFormat: "VERTUS möchte “%1$@” ausführen. Die Insel antwortet immer mit Nein, führe es also selbst im Terminal aus.",
        notFoundFormat: "Unter “%1$@” läuft nichts. Stelle den VERTUS-Befehl in den Einstellungen ein.",
        unreachableFormat: "VERTUS antwortet nicht mehr: %1$@",
        you: "Du",
        copyMessage: "Kopieren",
        editMessage: "Bearbeiten",
        approvalTitle: "VERTUS braucht deine Zustimmung",
        allowOnce: "Einmal erlauben",
        allowSession: "In diesem Chat erlauben",
        allowAlways: "Immer erlauben",
        deny: "Ablehnen",
        approvalAllowed: "Erlaubt.",
        approvalDenied: "Abgelehnt.",
        approvalExpired: "Die Anfrage ist abgelaufen, bevor eine Antwort kam.",
        reachedOut: "VERTUS hat sich gemeldet",
        reachedOutFormat: "VERTUS hat sich gemeldet · %1$@"
    )

    static let fr = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Parlez à VERTUS, qui tourne sur ce Mac, depuis l’îlot.",
        enable: "Afficher la conversation VERTUS dans l’îlot",
        cliPath: "Commande VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Lancée avec acp. VERTUS reste actif tant que ceci est activé.",
        requiresDynamicIsland: "La conversation VERTUS nécessite la Dynamic Island.",
        enableDynamicIsland: "Activer la Dynamic Island",
        connecting: "Démarrage de VERTUS…",
        ready: "Connecté",
        placeholder: "Demandez à VERTUS…",
        send: "Envoyer",
        stop: "Arrêter",
        clear: "Effacer la conversation",
        retry: "Réessayer",
        emptyTitle: "Demandez tout à VERTUS",
        emptySubtitle: "VERTUS tourne ici, avec les modèles et les outils que vous avez configurés.",
        thinking: "Réflexion",
        stopped: "Arrêté.",
        stoppedAtLimit: "La réponse a atteint sa limite de longueur.",
        stoppedAtStepLimit: "La réponse a atteint sa limite d’étapes.",
        refusedByAgent: "VERTUS a refusé cette demande.",
        refusedCommand: "VERTUS a demandé à exécuter un outil. L’îlot répond toujours non, exécutez-le vous-même dans un terminal.",
        refusedCommandFormat: "VERTUS a demandé à exécuter «\u{00A0}%1$@\u{00A0}». L’îlot répond toujours non, exécutez-le vous-même dans un terminal.",
        notFoundFormat: "Rien ne s’exécute à «\u{00A0}%1$@\u{00A0}». Définissez la commande VERTUS dans les Réglages.",
        unreachableFormat: "VERTUS ne répond plus\u{00A0}: %1$@",
        you: "Vous",
        copyMessage: "Copier",
        editMessage: "Modifier",
        approvalTitle: "VERTUS a besoin de votre accord",
        allowOnce: "Autoriser une fois",
        allowSession: "Autoriser dans cette conversation",
        allowAlways: "Toujours autoriser",
        deny: "Refuser",
        approvalAllowed: "Autorisé.",
        approvalDenied: "Refusé.",
        approvalExpired: "La demande a expiré avant une réponse.",
        reachedOut: "VERTUS vous a écrit",
        reachedOutFormat: "VERTUS vous a écrit · %1$@"
    )

    static let it = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Parla con VERTUS, in esecuzione su questo Mac, dall’isola.",
        enable: "Mostra il chat VERTUS nell’isola",
        cliPath: "Comando VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Eseguito con acp. VERTUS resta attivo finché questo è attivo.",
        requiresDynamicIsland: "Il chat VERTUS richiede la Dynamic Island.",
        enableDynamicIsland: "Attiva Dynamic Island",
        connecting: "Avvio di VERTUS…",
        ready: "Connesso",
        placeholder: "Chiedi a VERTUS…",
        send: "Invia",
        stop: "Ferma",
        clear: "Cancella conversazione",
        retry: "Riprova",
        emptyTitle: "Chiedi qualsiasi cosa a VERTUS",
        emptySubtitle: "VERTUS gira qui, con i modelli e gli strumenti che hai configurato.",
        thinking: "Sta pensando",
        stopped: "Fermato.",
        stoppedAtLimit: "La risposta ha raggiunto il limite di lunghezza.",
        stoppedAtStepLimit: "La risposta ha raggiunto il limite di passaggi.",
        refusedByAgent: "VERTUS ha rifiutato questa richiesta.",
        refusedCommand: "VERTUS ha chiesto di eseguire uno strumento. L’isola risponde sempre no, quindi eseguilo tu nel terminale.",
        refusedCommandFormat: "VERTUS ha chiesto di eseguire “%1$@”. L’isola risponde sempre no, quindi eseguilo tu nel terminale.",
        notFoundFormat: "Non viene eseguito nulla in “%1$@”. Imposta il comando VERTUS nelle Impostazioni.",
        unreachableFormat: "VERTUS non risponde più: %1$@",
        you: "Tu",
        copyMessage: "Copia",
        editMessage: "Modifica",
        approvalTitle: "VERTUS ha bisogno del tuo consenso",
        allowOnce: "Consenti una volta",
        allowSession: "Consenti in questa chat",
        allowAlways: "Consenti sempre",
        deny: "Nega",
        approvalAllowed: "Consentito.",
        approvalDenied: "Negato.",
        approvalExpired: "La richiesta è scaduta prima di una risposta.",
        reachedOut: "VERTUS ti ha scritto",
        reachedOutFormat: "VERTUS ti ha scritto · %1$@"
    )

    static let ru = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Общайтесь с VERTUS, запущенным на этом Mac, прямо из острова.",
        enable: "Показывать чат VERTUS в острове",
        cliPath: "Команда VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Запускается с acp. VERTUS работает, пока это включено.",
        requiresDynamicIsland: "Чату VERTUS нужен Dynamic Island.",
        enableDynamicIsland: "Включить Dynamic Island",
        connecting: "Запуск VERTUS…",
        ready: "Подключено",
        placeholder: "Спросите VERTUS…",
        send: "Отправить",
        stop: "Остановить",
        clear: "Очистить чат",
        retry: "Повторить",
        emptyTitle: "Спросите VERTUS о чём угодно",
        emptySubtitle: "VERTUS работает здесь, с моделями и инструментами, которые вы настроили.",
        thinking: "Думает",
        stopped: "Остановлено.",
        stoppedAtLimit: "Ответ достиг ограничения длины.",
        stoppedAtStepLimit: "Ответ достиг ограничения шагов.",
        refusedByAgent: "VERTUS отклонил этот запрос.",
        refusedCommand: "VERTUS попросил запустить инструмент. Остров всегда отвечает отказом, поэтому запустите его сами в терминале.",
        refusedCommandFormat: "VERTUS попросил запустить «%1$@». Остров всегда отвечает отказом, поэтому запустите его сами в терминале.",
        notFoundFormat: "По адресу «%1$@» ничего не запускается. Укажите команду VERTUS в настройках.",
        unreachableFormat: "VERTUS перестал отвечать: %1$@",
        you: "Вы",
        copyMessage: "Копировать",
        editMessage: "Изменить",
        approvalTitle: "VERTUS нужно ваше разрешение",
        allowOnce: "Разрешить один раз",
        allowSession: "Разрешить в этом чате",
        allowAlways: "Всегда разрешать",
        deny: "Запретить",
        approvalAllowed: "Разрешено.",
        approvalDenied: "Запрещено.",
        approvalExpired: "Запрос истёк до ответа.",
        reachedOut: "VERTUS написал вам",
        reachedOutFormat: "VERTUS написал вам · %1$@"
    )

    static let tr = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Bu Mac’te çalışan VERTUS ile adacıktan konuşun.",
        enable: "VERTUS Sohbetini adacıkta göster",
        cliPath: "VERTUS komutu",
        cliPathPlaceholder: "hermes",
        cliPathHint: "acp ile çalıştırılır. Bu açıkken VERTUS çalışmaya devam eder.",
        requiresDynamicIsland: "VERTUS Sohbeti Dynamic Island gerektirir.",
        enableDynamicIsland: "Dynamic Island’ı aç",
        connecting: "VERTUS başlatılıyor…",
        ready: "Bağlı",
        placeholder: "VERTUS’a sorun…",
        send: "Gönder",
        stop: "Durdur",
        clear: "Sohbeti temizle",
        retry: "Yeniden dene",
        emptyTitle: "VERTUS’a her şeyi sorun",
        emptySubtitle: "VERTUS burada, sizin ayarladığınız modeller ve araçlarla çalışır.",
        thinking: "Düşünüyor",
        stopped: "Durduruldu.",
        stoppedAtLimit: "Yanıt uzunluk sınırına ulaştı.",
        stoppedAtStepLimit: "Yanıt adım sınırına ulaştı.",
        refusedByAgent: "VERTUS bu isteği reddetti.",
        refusedCommand: "VERTUS bir araç çalıştırmak istedi. Adacık her zaman hayır der, bu yüzden gerekliyse terminalde kendiniz çalıştırın.",
        refusedCommandFormat: "VERTUS “%1$@” çalıştırmak istedi. Adacık her zaman hayır der, bu yüzden gerekliyse terminalde kendiniz çalıştırın.",
        notFoundFormat: "“%1$@” konumunda çalışan bir şey yok. VERTUS komutunu Ayarlar’da belirtin.",
        unreachableFormat: "VERTUS yanıt vermeyi bıraktı: %1$@",
        you: "Siz",
        copyMessage: "Kopyala",
        editMessage: "Düzenle",
        approvalTitle: "VERTUS onayınızı bekliyor",
        allowOnce: "Bir kez izin ver",
        allowSession: "Bu sohbette izin ver",
        allowAlways: "Her zaman izin ver",
        deny: "Reddet",
        approvalAllowed: "İzin verildi.",
        approvalDenied: "Reddedildi.",
        approvalExpired: "İstek yanıtlanmadan süresi doldu.",
        reachedOut: "VERTUS size yazdı",
        reachedOutFormat: "VERTUS size yazdı · %1$@"
    )

    static let ja = NotchHermesChatStrings(
        title: "VERTUS",
        description: "このMacで動くVERTUSと、アイランドから会話できます。",
        enable: "アイランドにVERTUSチャットを表示",
        cliPath: "VERTUSコマンド",
        cliPathPlaceholder: "hermes",
        cliPathHint: "acpで実行します。これがオンの間、VERTUSは動作し続けます。",
        requiresDynamicIsland: "VERTUSチャットにはDynamic Islandが必要です。",
        enableDynamicIsland: "Dynamic Islandをオンにする",
        connecting: "VERTUSを起動中…",
        ready: "接続済み",
        placeholder: "VERTUSに質問…",
        send: "送信",
        stop: "停止",
        clear: "会話を消去",
        retry: "再試行",
        emptyTitle: "VERTUSに何でも聞いてください",
        emptySubtitle: "VERTUSはこのMacで、設定したモデルとツールを使って動きます。",
        thinking: "考えています",
        stopped: "停止しました。",
        stoppedAtLimit: "返答が長さの上限に達しました。",
        stoppedAtStepLimit: "返答がステップ数の上限に達しました。",
        refusedByAgent: "VERTUSはこの依頼を断りました。",
        refusedCommand: "VERTUSがツールの実行を求めました。アイランドは常に拒否するため、必要ならターミナルでご自身で実行してください。",
        refusedCommandFormat: "VERTUSが「%1$@」の実行を求めました。アイランドは常に拒否するため、必要ならターミナルでご自身で実行してください。",
        notFoundFormat: "「%1$@」では何も実行されません。設定でVERTUSコマンドを指定してください。",
        unreachableFormat: "VERTUSが応答しなくなりました: %1$@",
        you: "あなた",
        copyMessage: "コピー",
        editMessage: "編集",
        approvalTitle: "VERTUSが許可を求めています",
        allowOnce: "今回だけ許可",
        allowSession: "このチャットで許可",
        allowAlways: "常に許可",
        deny: "拒否",
        approvalAllowed: "許可しました。",
        approvalDenied: "拒否しました。",
        approvalExpired: "応答する前に依頼の期限が切れました。",
        reachedOut: "VERTUSから連絡がありました",
        reachedOutFormat: "VERTUSから連絡がありました · %1$@"
    )

    static let ko = NotchHermesChatStrings(
        title: "VERTUS",
        description: "이 Mac에서 실행되는 VERTUS와 아일랜드에서 대화하세요.",
        enable: "아일랜드에 VERTUS 채팅 표시",
        cliPath: "VERTUS 명령",
        cliPathPlaceholder: "hermes",
        cliPathHint: "acp로 실행됩니다. 이 기능이 켜져 있는 동안 VERTUS가 계속 실행됩니다.",
        requiresDynamicIsland: "VERTUS 채팅에는 Dynamic Island가 필요합니다.",
        enableDynamicIsland: "Dynamic Island 켜기",
        connecting: "VERTUS 시작 중…",
        ready: "연결됨",
        placeholder: "VERTUS에게 물어보기…",
        send: "보내기",
        stop: "중지",
        clear: "대화 지우기",
        retry: "다시 시도",
        emptyTitle: "VERTUS에게 무엇이든 물어보세요",
        emptySubtitle: "VERTUS는 여기에서 설정한 모델과 도구로 실행됩니다.",
        thinking: "생각 중",
        stopped: "중지되었습니다.",
        stoppedAtLimit: "응답이 길이 한도에 도달했습니다.",
        stoppedAtStepLimit: "응답이 단계 한도에 도달했습니다.",
        refusedByAgent: "VERTUS가 이 요청을 거절했습니다.",
        refusedCommand: "VERTUS가 도구 실행을 요청했습니다. 아일랜드는 항상 거절하므로 필요하면 터미널에서 직접 실행하세요.",
        refusedCommandFormat: "VERTUS가 “%1$@” 실행을 요청했습니다. 아일랜드는 항상 거절하므로 필요하면 터미널에서 직접 실행하세요.",
        notFoundFormat: "“%1$@”에서 실행되는 것이 없습니다. 설정에서 VERTUS 명령을 지정하세요.",
        unreachableFormat: "VERTUS가 응답을 멈췄습니다: %1$@",
        you: "나",
        copyMessage: "복사",
        editMessage: "편집",
        approvalTitle: "VERTUS가 승인을 요청합니다",
        allowOnce: "한 번 허용",
        allowSession: "이 채팅에서 허용",
        allowAlways: "항상 허용",
        deny: "거부",
        approvalAllowed: "허용했습니다.",
        approvalDenied: "거부했습니다.",
        approvalExpired: "응답하기 전에 요청이 만료되었습니다.",
        reachedOut: "VERTUS가 먼저 연락했습니다",
        reachedOutFormat: "VERTUS가 먼저 연락했습니다 · %1$@"
    )

    static let uk = NotchHermesChatStrings(
        title: "VERTUS",
        description: "Спілкуйтеся з VERTUS, що працює на цьому Mac, просто з острова.",
        enable: "Показувати чат VERTUS в острові",
        cliPath: "Команда VERTUS",
        cliPathPlaceholder: "hermes",
        cliPathHint: "Запускається з acp. VERTUS працює, поки це ввімкнено.",
        requiresDynamicIsland: "Чату VERTUS потрібен Dynamic Island.",
        enableDynamicIsland: "Увімкнути Dynamic Island",
        connecting: "Запуск VERTUS…",
        ready: "Підключено",
        placeholder: "Запитайте в VERTUS…",
        send: "Надіслати",
        stop: "Зупинити",
        clear: "Очистити чат",
        retry: "Спробувати ще",
        emptyTitle: "Запитайте в VERTUS будь-що",
        emptySubtitle: "VERTUS працює тут, із моделями та інструментами, які ви налаштували.",
        thinking: "Думає",
        stopped: "Зупинено.",
        stoppedAtLimit: "Відповідь досягла обмеження довжини.",
        stoppedAtStepLimit: "Відповідь досягла обмеження кроків.",
        refusedByAgent: "VERTUS відхилив цей запит.",
        refusedCommand: "VERTUS попросив запустити інструмент. Острів завжди відмовляє, тож запустіть його самі в терміналі.",
        refusedCommandFormat: "VERTUS попросив запустити «%1$@». Острів завжди відмовляє, тож запустіть його самі в терміналі.",
        notFoundFormat: "За адресою «%1$@» нічого не запускається. Вкажіть команду VERTUS у налаштуваннях.",
        unreachableFormat: "VERTUS перестав відповідати: %1$@",
        you: "Ви",
        copyMessage: "Копіювати",
        editMessage: "Змінити",
        approvalTitle: "VERTUS потрібен ваш дозвіл",
        allowOnce: "Дозволити один раз",
        allowSession: "Дозволити в цьому чаті",
        allowAlways: "Завжди дозволяти",
        deny: "Заборонити",
        approvalAllowed: "Дозволено.",
        approvalDenied: "Заборонено.",
        approvalExpired: "Запит сплив до відповіді.",
        reachedOut: "VERTUS написав вам",
        reachedOutFormat: "VERTUS написав вам · %1$@"
    )

    static let zhHans = NotchHermesChatStrings(
        title: "VERTUS",
        description: "在灵动岛中与运行在这台 Mac 上的 VERTUS 对话。",
        enable: "在灵动岛中显示 VERTUS 聊天",
        cliPath: "VERTUS 命令",
        cliPathPlaceholder: "hermes",
        cliPathHint: "以 acp 运行。开启此项期间 VERTUS 会持续运行。",
        requiresDynamicIsland: "VERTUS 聊天需要 Dynamic Island。",
        enableDynamicIsland: "开启 Dynamic Island",
        connecting: "正在启动 VERTUS…",
        ready: "已连接",
        placeholder: "询问 VERTUS…",
        send: "发送",
        stop: "停止",
        clear: "清除对话",
        retry: "重试",
        emptyTitle: "向 VERTUS 提问",
        emptySubtitle: "VERTUS 在此运行，使用你为它设置的模型和工具。",
        thinking: "思考中",
        stopped: "已停止。",
        stoppedAtLimit: "回复已达到长度上限。",
        stoppedAtStepLimit: "回复已达到步骤上限。",
        refusedByAgent: "VERTUS 拒绝了这个请求。",
        refusedCommand: "VERTUS 请求运行一个工具。灵动岛一律拒绝，如需运行请在终端中自行执行。",
        refusedCommandFormat: "VERTUS 请求运行“%1$@”。灵动岛一律拒绝，如需运行请在终端中自行执行。",
        notFoundFormat: "“%1$@”处没有可运行的程序。请在设置中指定 VERTUS 命令。",
        unreachableFormat: "VERTUS 停止响应：%1$@",
        you: "你",
        copyMessage: "拷贝",
        editMessage: "编辑",
        approvalTitle: "VERTUS 需要你的批准",
        allowOnce: "允许一次",
        allowSession: "在此对话中允许",
        allowAlways: "始终允许",
        deny: "拒绝",
        approvalAllowed: "已允许。",
        approvalDenied: "已拒绝。",
        approvalExpired: "请求在回复前已过期。",
        reachedOut: "VERTUS 主动联系了你",
        reachedOutFormat: "VERTUS 主动联系了你 · %1$@"
    )

    static let zhTW = NotchHermesChatStrings(
        title: "VERTUS",
        description: "在動態島中與執行於這台 Mac 的 VERTUS 對話。",
        enable: "在動態島中顯示 VERTUS 聊天",
        cliPath: "VERTUS 指令",
        cliPathPlaceholder: "hermes",
        cliPathHint: "以 acp 執行。開啟此項期間 VERTUS 會持續執行。",
        requiresDynamicIsland: "VERTUS 聊天需要 Dynamic Island。",
        enableDynamicIsland: "開啟 Dynamic Island",
        connecting: "正在啟動 VERTUS…",
        ready: "已連線",
        placeholder: "詢問 VERTUS…",
        send: "傳送",
        stop: "停止",
        clear: "清除對話",
        retry: "重試",
        emptyTitle: "向 VERTUS 提問",
        emptySubtitle: "VERTUS 在此執行，使用你為它設定的模型與工具。",
        thinking: "思考中",
        stopped: "已停止。",
        stoppedAtLimit: "回覆已達到長度上限。",
        stoppedAtStepLimit: "回覆已達到步驟上限。",
        refusedByAgent: "VERTUS 拒絕了這個請求。",
        refusedCommand: "VERTUS 請求執行一個工具。動態島一律拒絕，如需執行請在終端機中自行執行。",
        refusedCommandFormat: "VERTUS 請求執行「%1$@」。動態島一律拒絕，如需執行請在終端機中自行執行。",
        notFoundFormat: "「%1$@」沒有可執行的程式。請在設定中指定 VERTUS 指令。",
        unreachableFormat: "VERTUS 停止回應：%1$@",
        you: "你",
        copyMessage: "拷貝",
        editMessage: "編輯",
        approvalTitle: "VERTUS 需要你的核准",
        allowOnce: "允許一次",
        allowSession: "在此對話中允許",
        allowAlways: "一律允許",
        deny: "拒絕",
        approvalAllowed: "已允許。",
        approvalDenied: "已拒絕。",
        approvalExpired: "請求在回覆前已過期。",
        reachedOut: "VERTUS 主動聯絡了你",
        reachedOutFormat: "VERTUS 主動聯絡了你 · %1$@"
    )

    static let zhHK = NotchHermesChatStrings(
        title: "VERTUS",
        description: "在動態島中與運行於這台 Mac 的 VERTUS 對話。",
        enable: "在動態島中顯示 VERTUS 聊天",
        cliPath: "VERTUS 指令",
        cliPathPlaceholder: "hermes",
        cliPathHint: "以 acp 執行。開啟此項期間 VERTUS 會持續運行。",
        requiresDynamicIsland: "VERTUS 聊天需要 Dynamic Island。",
        enableDynamicIsland: "開啟 Dynamic Island",
        connecting: "正在啟動 VERTUS…",
        ready: "已連接",
        placeholder: "詢問 VERTUS…",
        send: "傳送",
        stop: "停止",
        clear: "清除對話",
        retry: "重試",
        emptyTitle: "向 VERTUS 提問",
        emptySubtitle: "VERTUS 在此運行，使用你為它設定的模型與工具。",
        thinking: "思考中",
        stopped: "已停止。",
        stoppedAtLimit: "回覆已達到長度上限。",
        stoppedAtStepLimit: "回覆已達到步驟上限。",
        refusedByAgent: "VERTUS 拒絕了這個請求。",
        refusedCommand: "VERTUS 請求運行一個工具。動態島一律拒絕，如需運行請在終端機中自行執行。",
        refusedCommandFormat: "VERTUS 請求運行「%1$@」。動態島一律拒絕，如需運行請在終端機中自行執行。",
        notFoundFormat: "「%1$@」沒有可運行的程式。請在設定中指定 VERTUS 指令。",
        unreachableFormat: "VERTUS 停止回應：%1$@",
        you: "你",
        copyMessage: "拷貝",
        editMessage: "編輯",
        approvalTitle: "VERTUS 需要你的批准",
        allowOnce: "允許一次",
        allowSession: "在此對話中允許",
        allowAlways: "一律允許",
        deny: "拒絕",
        approvalAllowed: "已允許。",
        approvalDenied: "已拒絕。",
        approvalExpired: "請求在回覆前已逾時。",
        reachedOut: "VERTUS 主動聯絡你",
        reachedOutFormat: "VERTUS 主動聯絡你 · %1$@"
    )
}
