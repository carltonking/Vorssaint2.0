// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The agents' pages as Messages: replying to a message, files sent with
/// one, and how a notification names what has no words.
struct NotchAgentMessagingStrings {
    let reply: String
    let replyingTo: String
    let cancelReply: String
    let attach: String
    let removeAttachment: String
    let image: String
    let attachment: String
    let open: String
}

extension FeatureStrings {
    static func notchAgentMessaging(_ language: AppLanguage) -> NotchAgentMessagingStrings {
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

extension NotchAgentMessagingStrings {
    static let enUS = NotchAgentMessagingStrings(
        reply: "Reply",
        replyingTo: "Replying to",
        cancelReply: "Cancel Reply",
        attach: "Add Attachment",
        removeAttachment: "Remove",
        image: "Image",
        attachment: "Attachment",
        open: "Open"
    )

    static let ptBR = NotchAgentMessagingStrings(
        reply: "Responder",
        replyingTo: "Respondendo a",
        cancelReply: "Cancelar resposta",
        attach: "Adicionar anexo",
        removeAttachment: "Remover",
        image: "Imagem",
        attachment: "Anexo",
        open: "Abrir"
    )

    static let es = NotchAgentMessagingStrings(
        reply: "Responder",
        replyingTo: "Respondiendo a",
        cancelReply: "Cancelar respuesta",
        attach: "Añadir archivo adjunto",
        removeAttachment: "Quitar",
        image: "Imagen",
        attachment: "Archivo adjunto",
        open: "Abrir"
    )

    static let sk = NotchAgentMessagingStrings(
        reply: "Odpovedať",
        replyingTo: "Odpoveď na",
        cancelReply: "Zrušiť odpoveď",
        attach: "Pridať prílohu",
        removeAttachment: "Odstrániť",
        image: "Obrázok",
        attachment: "Príloha",
        open: "Otvoriť"
    )

    static let de = NotchAgentMessagingStrings(
        reply: "Antworten",
        replyingTo: "Antwort auf",
        cancelReply: "Antwort abbrechen",
        attach: "Anhang hinzufügen",
        removeAttachment: "Entfernen",
        image: "Bild",
        attachment: "Anhang",
        open: "Öffnen"
    )

    static let fr = NotchAgentMessagingStrings(
        reply: "Répondre",
        replyingTo: "Réponse à",
        cancelReply: "Annuler la réponse",
        attach: "Ajouter une pièce jointe",
        removeAttachment: "Retirer",
        image: "Image",
        attachment: "Pièce jointe",
        open: "Ouvrir"
    )

    static let it = NotchAgentMessagingStrings(
        reply: "Rispondi",
        replyingTo: "Risposta a",
        cancelReply: "Annulla risposta",
        attach: "Aggiungi allegato",
        removeAttachment: "Rimuovi",
        image: "Immagine",
        attachment: "Allegato",
        open: "Apri"
    )

    static let ru = NotchAgentMessagingStrings(
        reply: "Ответить",
        replyingTo: "Ответ на",
        cancelReply: "Отменить ответ",
        attach: "Добавить вложение",
        removeAttachment: "Удалить",
        image: "Изображение",
        attachment: "Вложение",
        open: "Открыть"
    )

    static let tr = NotchAgentMessagingStrings(
        reply: "Yanıtla",
        replyingTo: "Yanıtlanan",
        cancelReply: "Yanıtı iptal et",
        attach: "Ek ekle",
        removeAttachment: "Kaldır",
        image: "Görüntü",
        attachment: "Ek",
        open: "Aç"
    )

    static let ja = NotchAgentMessagingStrings(
        reply: "返信",
        replyingTo: "返信先",
        cancelReply: "返信をキャンセル",
        attach: "添付ファイルを追加",
        removeAttachment: "削除",
        image: "画像",
        attachment: "添付ファイル",
        open: "開く"
    )

    static let ko = NotchAgentMessagingStrings(
        reply: "답장",
        replyingTo: "답장 대상",
        cancelReply: "답장 취소",
        attach: "첨부 파일 추가",
        removeAttachment: "제거",
        image: "이미지",
        attachment: "첨부 파일",
        open: "열기"
    )

    static let uk = NotchAgentMessagingStrings(
        reply: "Відповісти",
        replyingTo: "Відповідь на",
        cancelReply: "Скасувати відповідь",
        attach: "Додати вкладення",
        removeAttachment: "Вилучити",
        image: "Зображення",
        attachment: "Вкладення",
        open: "Відкрити"
    )

    static let zhHans = NotchAgentMessagingStrings(
        reply: "回复",
        replyingTo: "回复",
        cancelReply: "取消回复",
        attach: "添加附件",
        removeAttachment: "移除",
        image: "图像",
        attachment: "附件",
        open: "打开"
    )

    static let zhTW = NotchAgentMessagingStrings(
        reply: "回覆",
        replyingTo: "回覆",
        cancelReply: "取消回覆",
        attach: "加入附件",
        removeAttachment: "移除",
        image: "影像",
        attachment: "附件",
        open: "打開"
    )

    static let zhHK = NotchAgentMessagingStrings(
        reply: "回覆",
        replyingTo: "回覆",
        cancelReply: "取消回覆",
        attach: "加入附件",
        removeAttachment: "移除",
        image: "影像",
        attachment: "附件",
        open: "打開"
    )
}
