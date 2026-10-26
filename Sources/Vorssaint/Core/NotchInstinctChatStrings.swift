// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// The Instinct page's own words. The page is VERTUS's chat page carrying a
/// different conversation, so everything they share (Send, Copy, Clear,
/// dictation) stays in `NotchHermesChatStrings` and only what names Instinct
/// or the Messages thread lives here. "Instinct" is a name and stays as it is
/// in every language.
struct NotchInstinctChatStrings {
    let title: String
    let description: String
    let enable: String
    let number: String
    let numberPlaceholder: String
    let numberHint: String
    let connecting: String
    let placeholder: String
    let emptyTitle: String
    let emptySubtitle: String
    let noNumber: String
    let toolMissingFormat: String
    let fullDiskAccessFormat: String
    let openFullDiskAccess: String
    let reachedOut: String
    let unreachableFormat: String
    let waiting: String
    let stopped: String
    let openLink: String

    /// Why the thread cannot be read, naming the app that needs the grant:
    /// a developer build is a separate entry in System Settings.
    func fullDiskAccess(_ app: String) -> String { String(format: fullDiskAccessFormat, app) }

    /// The shared chat page's words with Instinct's in place of VERTUS's.
    func chat(_ base: NotchHermesChatStrings) -> NotchHermesChatStrings {
        var words = base
        words.title = title
        words.description = description
        words.enable = enable
        words.connecting = connecting
        words.placeholder = placeholder
        words.emptyTitle = emptyTitle
        words.emptySubtitle = emptySubtitle
        words.thinking = waiting
        words.stopped = stopped
        words.notFoundFormat = toolMissingFormat
        words.unreachableFormat = unreachableFormat
        words.reachedOut = reachedOut
        // Instinct has no routines the page could name.
        words.reachedOutFormat = "\(reachedOut) · %1$@"
        return words
    }
}

extension FeatureStrings {
    static func notchInstinctChat(_ language: AppLanguage) -> NotchInstinctChatStrings {
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

extension NotchInstinctChatStrings {
    static let enUS = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Text Instinct from the island. The conversation is your iMessage thread with Instinct, the same one on your phone.",
        enable: "Show Instinct in the island",
        number: "Instinct’s number",
        numberPlaceholder: "+1 555 123 4567",
        numberHint: "The phone number or email you text Instinct at. It stays on this Mac and is left out of settings backups.",
        connecting: "Opening your thread with Instinct…",
        placeholder: "Message Instinct…",
        emptyTitle: "Text Instinct anything",
        emptySubtitle: "Messages go to Instinct over iMessage. Replies show up here and on your phone.",
        noNumber: "Add Instinct’s number in the island’s settings to start.",
        toolMissingFormat: "Nothing runs at “%1$@”. Instinct needs the imsg tool to read and send your iMessages.",
        fullDiskAccessFormat: "Reading your messages needs Full Disk Access for %1$@. Turn it on in System Settings, then try again.",
        openFullDiskAccess: "Open Full Disk Access",
        reachedOut: "Instinct wrote",
        unreachableFormat: "Messages did not answer: %1$@",
        waiting: "Waiting for Instinct",
        stopped: "Stopped waiting. Instinct may still reply.",
        openLink: "Open Link"
    )

    static let ptBR = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Mande mensagens ao Instinct pela ilha. A conversa é a sua conversa do iMessage com o Instinct, a mesma do seu celular.",
        enable: "Mostrar o Instinct na ilha",
        number: "Número do Instinct",
        numberPlaceholder: "+55 11 91234 5678",
        numberHint: "O telefone ou e-mail para o qual você manda mensagens ao Instinct. Fica neste Mac e não entra nos backups de ajustes.",
        connecting: "Abrindo sua conversa com o Instinct…",
        placeholder: "Mensagem para o Instinct…",
        emptyTitle: "Mande qualquer coisa ao Instinct",
        emptySubtitle: "As mensagens vão ao Instinct pelo iMessage. As respostas aparecem aqui e no seu celular.",
        noNumber: "Adicione o número do Instinct nos ajustes da ilha para começar.",
        toolMissingFormat: "Nada roda em “%1$@”. O Instinct precisa da ferramenta imsg para ler e enviar suas mensagens do iMessage.",
        fullDiskAccessFormat: "Ler suas mensagens exige Acesso Total ao Disco para %1$@. Ative nos Ajustes do Sistema e tente de novo.",
        openFullDiskAccess: "Abrir Acesso Total ao Disco",
        reachedOut: "O Instinct escreveu",
        unreachableFormat: "O Mensagens não respondeu: %1$@",
        waiting: "Aguardando o Instinct",
        stopped: "Parou de aguardar. O Instinct ainda pode responder.",
        openLink: "Abrir link"
    )

    static let es = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Escribe a Instinct desde la isla. La conversación es tu hilo de iMessage con Instinct, el mismo que en tu teléfono.",
        enable: "Mostrar Instinct en la isla",
        number: "Número de Instinct",
        numberPlaceholder: "+34 612 34 56 78",
        numberHint: "El teléfono o correo al que escribes a Instinct. Se queda en este Mac y no entra en las copias de los ajustes.",
        connecting: "Abriendo tu hilo con Instinct…",
        placeholder: "Mensaje para Instinct…",
        emptyTitle: "Escribe a Instinct lo que quieras",
        emptySubtitle: "Los mensajes van a Instinct por iMessage. Las respuestas aparecen aquí y en tu teléfono.",
        noNumber: "Añade el número de Instinct en los ajustes de la isla para empezar.",
        toolMissingFormat: "No hay nada en “%1$@”. Instinct necesita la herramienta imsg para leer y enviar tus iMessages.",
        fullDiskAccessFormat: "Leer tus mensajes requiere Acceso total al disco para %1$@. Actívalo en Ajustes del Sistema y vuelve a intentarlo.",
        openFullDiskAccess: "Abrir Acceso total al disco",
        reachedOut: "Instinct escribió",
        unreachableFormat: "Mensajes no respondió: %1$@",
        waiting: "Esperando a Instinct",
        stopped: "Se dejó de esperar. Instinct aún puede responder.",
        openLink: "Abrir enlace"
    )

    static let sk = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Píšte Instinctu z ostrova. Konverzácia je vaše vlákno v iMessage s Instinctom, to isté ako v telefóne.",
        enable: "Zobraziť Instinct na ostrove",
        number: "Číslo Instinctu",
        numberPlaceholder: "+421 912 345 678",
        numberHint: "Telefónne číslo alebo e-mail, na ktorý píšete Instinctu. Zostáva na tomto Macu a nie je súčasťou záloh nastavení.",
        connecting: "Otvára sa vlákno s Instinctom…",
        placeholder: "Správa pre Instinct…",
        emptyTitle: "Napíšte Instinctu čokoľvek",
        emptySubtitle: "Správy idú Instinctu cez iMessage. Odpovede sa zobrazia tu aj v telefóne.",
        noNumber: "Na začiatok pridajte číslo Instinctu v nastaveniach ostrova.",
        toolMissingFormat: "Na „%1$@“ nič nebeží. Instinct potrebuje nástroj imsg na čítanie a odosielanie správ iMessage.",
        fullDiskAccessFormat: "Čítanie správ vyžaduje Úplný prístup k disku pre %1$@. Zapnite ho v Systémových nastaveniach a skúste znova.",
        openFullDiskAccess: "Otvoriť Úplný prístup k disku",
        reachedOut: "Instinct napísal",
        unreachableFormat: "Správy neodpovedali: %1$@",
        waiting: "Čaká sa na Instinct",
        stopped: "Čakanie zastavené. Instinct ešte môže odpovedať.",
        openLink: "Otvoriť odkaz"
    )

    static let de = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Schreib Instinct von der Insel aus. Die Unterhaltung ist dein iMessage-Verlauf mit Instinct, derselbe wie auf deinem Telefon.",
        enable: "Instinct in der Insel zeigen",
        number: "Nummer von Instinct",
        numberPlaceholder: "+49 151 23456789",
        numberHint: "Die Telefonnummer oder E-Mail, an die du Instinct schreibst. Sie bleibt auf diesem Mac und ist nicht Teil von Einstellungs-Backups.",
        connecting: "Verlauf mit Instinct wird geöffnet…",
        placeholder: "Nachricht an Instinct…",
        emptyTitle: "Schreib Instinct, was du willst",
        emptySubtitle: "Nachrichten gehen per iMessage an Instinct. Antworten erscheinen hier und auf deinem Telefon.",
        noNumber: "Trag zum Start die Nummer von Instinct in den Einstellungen der Insel ein.",
        toolMissingFormat: "Unter „%1$@“ läuft nichts. Instinct braucht das Tool imsg, um deine iMessages zu lesen und zu senden.",
        fullDiskAccessFormat: "Zum Lesen deiner Nachrichten braucht %1$@ Festplattenvollzugriff. Schalte ihn in den Systemeinstellungen ein und versuch es erneut.",
        openFullDiskAccess: "Festplattenvollzugriff öffnen",
        reachedOut: "Instinct hat geschrieben",
        unreachableFormat: "Nachrichten hat nicht geantwortet: %1$@",
        waiting: "Warten auf Instinct",
        stopped: "Warten beendet. Instinct kann noch antworten.",
        openLink: "Link öffnen"
    )

    static let fr = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Écrivez à Instinct depuis l’île. La conversation est votre fil iMessage avec Instinct, le même que sur votre téléphone.",
        enable: "Afficher Instinct dans l’île",
        number: "Numéro d’Instinct",
        numberPlaceholder: "+33 6 12 34 56 78",
        numberHint: "Le numéro ou l’e-mail auquel vous écrivez à Instinct. Il reste sur ce Mac et n’est pas inclus dans les sauvegardes des réglages.",
        connecting: "Ouverture de votre fil avec Instinct…",
        placeholder: "Message à Instinct…",
        emptyTitle: "Écrivez ce que vous voulez à Instinct",
        emptySubtitle: "Les messages partent vers Instinct par iMessage. Les réponses s’affichent ici et sur votre téléphone.",
        noNumber: "Ajoutez le numéro d’Instinct dans les réglages de l’île pour commencer.",
        toolMissingFormat: "Rien ne s’exécute à « %1$@ ». Instinct a besoin de l’outil imsg pour lire et envoyer vos iMessages.",
        fullDiskAccessFormat: "Lire vos messages nécessite l’accès complet au disque pour %1$@. Activez-le dans Réglages Système, puis réessayez.",
        openFullDiskAccess: "Ouvrir l’accès complet au disque",
        reachedOut: "Instinct a écrit",
        unreachableFormat: "Messages n’a pas répondu : %1$@",
        waiting: "En attente d’Instinct",
        stopped: "Attente arrêtée. Instinct peut encore répondre.",
        openLink: "Ouvrir le lien"
    )

    static let it = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Scrivi a Instinct dall’isola. La conversazione è il tuo thread iMessage con Instinct, lo stesso del telefono.",
        enable: "Mostra Instinct nell’isola",
        number: "Numero di Instinct",
        numberPlaceholder: "+39 312 345 6789",
        numberHint: "Il numero o l’e-mail a cui scrivi a Instinct. Resta su questo Mac ed è escluso dai backup delle impostazioni.",
        connecting: "Apertura del thread con Instinct…",
        placeholder: "Messaggio a Instinct…",
        emptyTitle: "Scrivi qualsiasi cosa a Instinct",
        emptySubtitle: "I messaggi vanno a Instinct tramite iMessage. Le risposte compaiono qui e sul telefono.",
        noNumber: "Per iniziare, aggiungi il numero di Instinct nelle impostazioni dell’isola.",
        toolMissingFormat: "Non c’è niente in “%1$@”. Instinct ha bisogno dello strumento imsg per leggere e inviare i tuoi iMessage.",
        fullDiskAccessFormat: "Per leggere i messaggi serve l’accesso completo al disco per %1$@. Attivalo in Impostazioni di Sistema, poi riprova.",
        openFullDiskAccess: "Apri Accesso completo al disco",
        reachedOut: "Instinct ha scritto",
        unreachableFormat: "Messaggi non ha risposto: %1$@",
        waiting: "In attesa di Instinct",
        stopped: "Attesa interrotta. Instinct può ancora rispondere.",
        openLink: "Apri link"
    )

    static let ru = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Пишите Instinct прямо с острова. Это ваша переписка с Instinct в iMessage, та же, что на телефоне.",
        enable: "Показывать Instinct на острове",
        number: "Номер Instinct",
        numberPlaceholder: "+7 912 345-67-89",
        numberHint: "Номер телефона или e-mail, на который вы пишете Instinct. Он остается на этом Mac и не попадает в резервные копии настроек.",
        connecting: "Открывается переписка с Instinct…",
        placeholder: "Сообщение для Instinct…",
        emptyTitle: "Напишите Instinct что угодно",
        emptySubtitle: "Сообщения уходят Instinct через iMessage. Ответы появляются здесь и на телефоне.",
        noNumber: "Чтобы начать, добавьте номер Instinct в настройках острова.",
        toolMissingFormat: "По пути «%1$@» ничего нет. Instinct нужен инструмент imsg, чтобы читать и отправлять ваши iMessage.",
        fullDiskAccessFormat: "Для чтения сообщений %1$@ нужен полный доступ к диску. Включите его в Системных настройках и попробуйте снова.",
        openFullDiskAccess: "Открыть полный доступ к диску",
        reachedOut: "Instinct написал",
        unreachableFormat: "Сообщения не ответили: %1$@",
        waiting: "Ожидание Instinct",
        stopped: "Ожидание остановлено. Instinct еще может ответить.",
        openLink: "Открыть ссылку"
    )

    static let tr = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Instinct’e adadan yazın. Sohbet, Instinct ile olan iMessage yazışmanızdır; telefonunuzdakiyle aynıdır.",
        enable: "Instinct’i adada göster",
        number: "Instinct’in numarası",
        numberPlaceholder: "+90 532 123 45 67",
        numberHint: "Instinct’e yazdığınız telefon numarası veya e-posta. Bu Mac’te kalır ve ayar yedeklerine dahil edilmez.",
        connecting: "Instinct ile yazışmanız açılıyor…",
        placeholder: "Instinct’e mesaj…",
        emptyTitle: "Instinct’e istediğinizi yazın",
        emptySubtitle: "Mesajlar Instinct’e iMessage ile gider. Yanıtlar burada ve telefonunuzda görünür.",
        noNumber: "Başlamak için adanın ayarlarına Instinct’in numarasını ekleyin.",
        toolMissingFormat: "“%1$@” konumunda hiçbir şey çalışmıyor. Instinct, iMessage’larınızı okumak ve göndermek için imsg aracına ihtiyaç duyar.",
        fullDiskAccessFormat: "Mesajlarınızı okumak için %1$@ uygulamasına Tam Disk Erişimi gerekir. Sistem Ayarları’nda açın ve yeniden deneyin.",
        openFullDiskAccess: "Tam Disk Erişimi’ni Aç",
        reachedOut: "Instinct yazdı",
        unreachableFormat: "Mesajlar yanıt vermedi: %1$@",
        waiting: "Instinct bekleniyor",
        stopped: "Beklemeyi bıraktı. Instinct yine de yanıt verebilir.",
        openLink: "Bağlantıyı Aç"
    )

    static let ja = NotchInstinctChatStrings(
        title: "Instinct",
        description: "アイランドからInstinctにメッセージを送れます。会話はInstinctとのiMessageのスレッドで、iPhoneと同じものです。",
        enable: "アイランドにInstinctを表示",
        number: "Instinctの番号",
        numberPlaceholder: "+81 90-1234-5678",
        numberHint: "Instinctに送る電話番号またはメールアドレス。このMacにだけ保存され、設定のバックアップには含まれません。",
        connecting: "Instinctとのスレッドを開いています…",
        placeholder: "Instinctへのメッセージ…",
        emptyTitle: "Instinctに何でも送れます",
        emptySubtitle: "メッセージはiMessageでInstinctに届きます。返信はここと電話に表示されます。",
        noNumber: "始めるには、アイランドの設定でInstinctの番号を追加してください。",
        toolMissingFormat: "“%1$@”には何もありません。InstinctがiMessageを読んで送るにはimsgツールが必要です。",
        fullDiskAccessFormat: "メッセージを読むには%1$@にフルディスクアクセスが必要です。システム設定でオンにしてから、もう一度お試しください。",
        openFullDiskAccess: "フルディスクアクセスを開く",
        reachedOut: "Instinctからのメッセージ",
        unreachableFormat: "メッセージが応答しませんでした: %1$@",
        waiting: "Instinctを待っています",
        stopped: "待つのをやめました。Instinctはまだ返信するかもしれません。",
        openLink: "リンクを開く"
    )

    static let ko = NotchInstinctChatStrings(
        title: "Instinct",
        description: "아일랜드에서 Instinct에게 메시지를 보내세요. 대화는 휴대폰과 같은 Instinct와의 iMessage 대화입니다.",
        enable: "아일랜드에 Instinct 표시",
        number: "Instinct 번호",
        numberPlaceholder: "+82 10-1234-5678",
        numberHint: "Instinct에게 메시지를 보내는 전화번호나 이메일입니다. 이 Mac에만 남고 설정 백업에는 포함되지 않습니다.",
        connecting: "Instinct와의 대화를 여는 중…",
        placeholder: "Instinct에게 메시지…",
        emptyTitle: "Instinct에게 무엇이든 보내세요",
        emptySubtitle: "메시지는 iMessage로 Instinct에게 전달됩니다. 답장은 여기와 휴대폰에 표시됩니다.",
        noNumber: "시작하려면 아일랜드 설정에 Instinct 번호를 추가하세요.",
        toolMissingFormat: "“%1$@”에서 실행되는 것이 없습니다. Instinct가 iMessage를 읽고 보내려면 imsg 도구가 필요합니다.",
        fullDiskAccessFormat: "메시지를 읽으려면 %1$@에 전체 디스크 접근 권한이 필요합니다. 시스템 설정에서 켠 다음 다시 시도하세요.",
        openFullDiskAccess: "전체 디스크 접근 권한 열기",
        reachedOut: "Instinct가 보낸 메시지",
        unreachableFormat: "메시지 앱이 응답하지 않음: %1$@",
        waiting: "Instinct를 기다리는 중",
        stopped: "기다리기를 멈췄습니다. Instinct가 아직 답장할 수 있습니다.",
        openLink: "링크 열기"
    )

    static let uk = NotchInstinctChatStrings(
        title: "Instinct",
        description: "Пишіть Instinct просто з острова. Це ваше листування з Instinct в iMessage, те саме, що на телефоні.",
        enable: "Показувати Instinct на острові",
        number: "Номер Instinct",
        numberPlaceholder: "+380 67 123 4567",
        numberHint: "Номер телефону або e-mail, на який ви пишете Instinct. Він лишається на цьому Mac і не потрапляє до резервних копій налаштувань.",
        connecting: "Відкривається листування з Instinct…",
        placeholder: "Повідомлення для Instinct…",
        emptyTitle: "Напишіть Instinct будь-що",
        emptySubtitle: "Повідомлення надходять Instinct через iMessage. Відповіді з’являються тут і на телефоні.",
        noNumber: "Щоб почати, додайте номер Instinct у налаштуваннях острова.",
        toolMissingFormat: "За шляхом «%1$@» нічого немає. Instinct потрібен інструмент imsg, щоб читати й надсилати ваші iMessage.",
        fullDiskAccessFormat: "Щоб читати повідомлення, %1$@ потрібен повний доступ до диска. Увімкніть його в Системних параметрах і спробуйте ще раз.",
        openFullDiskAccess: "Відкрити повний доступ до диска",
        reachedOut: "Instinct написав",
        unreachableFormat: "Повідомлення не відповіли: %1$@",
        waiting: "Очікування Instinct",
        stopped: "Очікування зупинено. Instinct ще може відповісти.",
        openLink: "Відкрити посилання"
    )

    static let zhHans = NotchInstinctChatStrings(
        title: "Instinct",
        description: "在岛中给 Instinct 发消息。对话就是你与 Instinct 的 iMessage 对话，与手机上的相同。",
        enable: "在岛中显示 Instinct",
        number: "Instinct 的号码",
        numberPlaceholder: "+86 138 0013 8000",
        numberHint: "你给 Instinct 发消息所用的电话号码或电子邮件。它只保存在这台 Mac 上，不会包含在设置备份中。",
        connecting: "正在打开与 Instinct 的对话…",
        placeholder: "给 Instinct 发消息…",
        emptyTitle: "给 Instinct 发任何内容",
        emptySubtitle: "消息通过 iMessage 发送给 Instinct。回复会显示在这里和你的手机上。",
        noNumber: "请先在岛的设置中添加 Instinct 的号码。",
        toolMissingFormat: "“%1$@”处没有可运行的内容。Instinct 需要 imsg 工具来读取和发送你的 iMessage。",
        fullDiskAccessFormat: "读取消息需要为 %1$@ 开启完全磁盘访问权限。请在系统设置中开启，然后重试。",
        openFullDiskAccess: "打开完全磁盘访问权限",
        reachedOut: "Instinct 发来消息",
        unreachableFormat: "信息未响应：%1$@",
        waiting: "正在等待 Instinct",
        stopped: "已停止等待。Instinct 仍可能回复。",
        openLink: "打开链接"
    )

    static let zhTW = NotchInstinctChatStrings(
        title: "Instinct",
        description: "在島中傳訊息給 Instinct。對話就是你與 Instinct 的 iMessage 對話，與手機上的相同。",
        enable: "在島中顯示 Instinct",
        number: "Instinct 的號碼",
        numberPlaceholder: "+886 912 345 678",
        numberHint: "你傳訊息給 Instinct 所用的電話號碼或電子郵件。它只保存在這台 Mac 上，不會包含在設定備份中。",
        connecting: "正在打開與 Instinct 的對話…",
        placeholder: "傳訊息給 Instinct…",
        emptyTitle: "傳任何內容給 Instinct",
        emptySubtitle: "訊息會透過 iMessage 傳給 Instinct。回覆會顯示在這裡和你的手機上。",
        noNumber: "請先在島的設定中加入 Instinct 的號碼。",
        toolMissingFormat: "「%1$@」沒有可執行的項目。Instinct 需要 imsg 工具來讀取和傳送你的 iMessage。",
        fullDiskAccessFormat: "讀取訊息需要為 %1$@ 開啟完整磁碟取用權限。請在系統設定中開啟，然後再試一次。",
        openFullDiskAccess: "打開完整磁碟取用權限",
        reachedOut: "Instinct 傳來訊息",
        unreachableFormat: "訊息未回應：%1$@",
        waiting: "正在等待 Instinct",
        stopped: "已停止等待。Instinct 仍可能回覆。",
        openLink: "打開連結"
    )

    static let zhHK = NotchInstinctChatStrings(
        title: "Instinct",
        description: "在島中傳訊息給 Instinct。對話就是你與 Instinct 的 iMessage 對話，與手機上的相同。",
        enable: "在島中顯示 Instinct",
        number: "Instinct 的號碼",
        numberPlaceholder: "+852 5123 4567",
        numberHint: "你傳訊息給 Instinct 所用的電話號碼或電郵。它只保存在這部 Mac 上，不會包括在設定備份中。",
        connecting: "正在打開與 Instinct 的對話…",
        placeholder: "傳訊息給 Instinct…",
        emptyTitle: "傳任何內容給 Instinct",
        emptySubtitle: "訊息會經 iMessage 傳給 Instinct。回覆會顯示在這裡和你的手機上。",
        noNumber: "請先在島的設定中加入 Instinct 的號碼。",
        toolMissingFormat: "「%1$@」沒有可執行的項目。Instinct 需要 imsg 工具來讀取和傳送你的 iMessage。",
        fullDiskAccessFormat: "讀取訊息需要為 %1$@ 開啟完全磁碟取用權限。請在系統設定中開啟，然後再試一次。",
        openFullDiskAccess: "打開完全磁碟取用權限",
        reachedOut: "Instinct 傳來訊息",
        unreachableFormat: "訊息未有回應：%1$@",
        waiting: "正在等待 Instinct",
        stopped: "已停止等待。Instinct 仍可能回覆。",
        openLink: "打開連結"
    )
}
