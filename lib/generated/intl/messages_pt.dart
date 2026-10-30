// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a pt locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'pt';

  static String m0(name) =>
      "Foi encontrado um rascunho não salvo de ${name}. Recuperá-lo?";

  static String m1(date) => "Última modificação: ${date}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "abort": MessageLookupByLibrary.simpleMessage("Abortar"),
    "about": MessageLookupByLibrary.simpleMessage("Sobre"),
    "aboutXournal": MessageLookupByLibrary.simpleMessage("Sobre o Xournal++"),
    "aboutXournalMobileEdition": MessageLookupByLibrary.simpleMessage(
      "Sobre o Xournal++ Mobile",
    ),
    "addPage": MessageLookupByLibrary.simpleMessage("Adicionar página"),
    "alsoDeleteFile": MessageLookupByLibrary.simpleMessage(
      "Excluir também o arquivo do dispositivo (não pode ser desfeito)",
    ),
    "apply": MessageLookupByLibrary.simpleMessage("Aplicar"),
    "areYouSureIHaveThePermissionAndAreYou":
        MessageLookupByLibrary.simpleMessage(
          ". Tem certeza de que tenho a permissão necessária? E tem certeza de que é um arquivo Xournal++?",
        ),
    "areYouSureToDeleteTheSelectedFileThisCannot":
        MessageLookupByLibrary.simpleMessage(
          "Remover este documento da lista de recentes? O arquivo permanecerá no dispositivo, a menos que você escolha excluí-lo.",
        ),
    "background": MessageLookupByLibrary.simpleMessage("Background"),
    "between1And": MessageLookupByLibrary.simpleMessage("Entre 1 e"),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancelar"),
    "close": MessageLookupByLibrary.simpleMessage("Fechar"),
    "color": MessageLookupByLibrary.simpleMessage("Cor"),
    "confirmDelete": MessageLookupByLibrary.simpleMessage(
      "Esquecer documento recente",
    ),
    "copyErrorMessage": MessageLookupByLibrary.simpleMessage(
      "Copiar mensagem de erro",
    ),
    "couldNotFindBackgroundPdfSelectNewOne":
        MessageLookupByLibrary.simpleMessage(
          "Não foi possível encontrar o PDF de fundo. Selecione um novo",
        ),
    "delete": MessageLookupByLibrary.simpleMessage("Deletar"),
    "deletePage": MessageLookupByLibrary.simpleMessage("Deletar página"),
    "dotted": MessageLookupByLibrary.simpleMessage("Pontilhado"),
    "doubleTapToChange": MessageLookupByLibrary.simpleMessage(
      "Clique duplo para mudar.",
    ),
    "dropFilesToOpen": MessageLookupByLibrary.simpleMessage(
      "Arraste arquivos para abrir",
    ),
    "eraser": MessageLookupByLibrary.simpleMessage("Apagador"),
    "error": MessageLookupByLibrary.simpleMessage("Erro"),
    "errorLoadingFile": MessageLookupByLibrary.simpleMessage(
      "Erro carregando arquivo",
    ),
    "errorOpeningFile": MessageLookupByLibrary.simpleMessage(
      "Erro abrindo arquivo",
    ),
    "forgetRecent": MessageLookupByLibrary.simpleMessage("Esquecer"),
    "googleDriveConnect": MessageLookupByLibrary.simpleMessage(
      "Conectar ao Google Drive",
    ),
    "googleDriveConnected": MessageLookupByLibrary.simpleMessage("Conectado"),
    "graph": MessageLookupByLibrary.simpleMessage("Gráfico"),
    "highlighter": MessageLookupByLibrary.simpleMessage("Marcador"),
    "home": MessageLookupByLibrary.simpleMessage("Início"),
    "imVerySorryButICouldntReadTheFile": MessageLookupByLibrary.simpleMessage(
      "Sinto muito, mas não pude ler o arquivo.",
    ),
    "image": MessageLookupByLibrary.simpleMessage("Imagem"),
    "importPdf": MessageLookupByLibrary.simpleMessage("Importar PDF"),
    "latexNotImplemented": MessageLookupByLibrary.simpleMessage(
      "LaTeX (não implementado)",
    ),
    "lined": MessageLookupByLibrary.simpleMessage("Com linhas"),
    "loadingFile": MessageLookupByLibrary.simpleMessage(
      "Carregando arquivo...",
    ),
    "localStorage": MessageLookupByLibrary.simpleMessage("Armazenamento local"),
    "mb": MessageLookupByLibrary.simpleMessage("MB"),
    "mobileEditionUnofficial": MessageLookupByLibrary.simpleMessage(
      "Aplicativo móvel oficial",
    ),
    "move": MessageLookupByLibrary.simpleMessage("Mover"),
    "movePage": MessageLookupByLibrary.simpleMessage("Mover página"),
    "newDocument": MessageLookupByLibrary.simpleMessage("Novo Documento"),
    "newFile": MessageLookupByLibrary.simpleMessage("Novo"),
    "newNotebook": MessageLookupByLibrary.simpleMessage("Novo caderno"),
    "newPageIndex": MessageLookupByLibrary.simpleMessage("Nova página índice"),
    "newTitle": MessageLookupByLibrary.simpleMessage("Novo título"),
    "nextcloudAddress": MessageLookupByLibrary.simpleMessage(
      "Endereço do servidor Nextcloud",
    ),
    "nextcloudCancelLogin": MessageLookupByLibrary.simpleMessage(
      "Cancelar login",
    ),
    "nextcloudChooseFolder": MessageLookupByLibrary.simpleMessage(
      "Escolher uma pasta",
    ),
    "nextcloudConnect": MessageLookupByLibrary.simpleMessage("Conectar"),
    "nextcloudDisconnect": MessageLookupByLibrary.simpleMessage("Desconectar"),
    "nextcloudNotConnected": MessageLookupByLibrary.simpleMessage(
      "Não conectado",
    ),
    "nextcloudParentFolder": MessageLookupByLibrary.simpleMessage(
      "Pasta superior",
    ),
    "nextcloudReplace": MessageLookupByLibrary.simpleMessage("Substituir"),
    "nextcloudReplaceMessage": MessageLookupByLibrary.simpleMessage(
      "Já existe um caderno com este nome. Substituí-lo?",
    ),
    "nextcloudReplaceTitle": MessageLookupByLibrary.simpleMessage(
      "Substituir caderno?",
    ),
    "nextcloudUseFolder": MessageLookupByLibrary.simpleMessage(
      "Usar esta pasta",
    ),
    "noFileSelected": MessageLookupByLibrary.simpleMessage(
      "Nenhum arquivo selecionado",
    ),
    "noRecentFiles": MessageLookupByLibrary.simpleMessage(
      "Nenhum arquivo recente.",
    ),
    "noSavedNotebooks": MessageLookupByLibrary.simpleMessage(
      "Ainda não há cadernos salvos.",
    ),
    "notImplemented": MessageLookupByLibrary.simpleMessage(
      " (Não implementado)",
    ),
    "notWorkingYet": MessageLookupByLibrary.simpleMessage(
      "Não está funcionando ainda.",
    ),
    "okay": MessageLookupByLibrary.simpleMessage("Okay"),
    "open": MessageLookupByLibrary.simpleMessage("Abrir"),
    "opening": MessageLookupByLibrary.simpleMessage("Abrindo"),
    "openingFile": MessageLookupByLibrary.simpleMessage("Abrindo arquivo"),
    "pageBackground": MessageLookupByLibrary.simpleMessage(
      "Background da página",
    ),
    "pdf": MessageLookupByLibrary.simpleMessage("PDF"),
    "pen": MessageLookupByLibrary.simpleMessage("Caneta"),
    "quota": MessageLookupByLibrary.simpleMessage("Cota"),
    "recentBackendUnavailable": MessageLookupByLibrary.simpleMessage(
      "O armazenamento não está disponível. Reconecte a conta e a pasta originais.",
    ),
    "recentFiles": MessageLookupByLibrary.simpleMessage("Arquivos recentes"),
    "recoveryDiscard": MessageLookupByLibrary.simpleMessage(
      "Descartar rascunho",
    ),
    "recoveryLater": MessageLookupByLibrary.simpleMessage("Depois"),
    "recoveryLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Não foi possível verificar os rascunhos de recuperação.",
    ),
    "recoveryMessage": m0,
    "recoveryOpen": MessageLookupByLibrary.simpleMessage("Recuperar"),
    "recoverySaveFailed": MessageLookupByLibrary.simpleMessage(
      "Não foi possível salvar o rascunho de recuperação. Salve seu trabalho manualmente.",
    ),
    "recoveryTitle": MessageLookupByLibrary.simpleMessage(
      "Recuperar trabalho não salvo?",
    ),
    "removeSavedNotebook": MessageLookupByLibrary.simpleMessage(
      "Remover dos cadernos salvos",
    ),
    "ruled": MessageLookupByLibrary.simpleMessage("Com linhas e margem"),
    "save": MessageLookupByLibrary.simpleMessage("Salvar"),
    "saveAs": MessageLookupByLibrary.simpleMessage("Salvar como..."),
    "savedNotebooks": MessageLookupByLibrary.simpleMessage("Cadernos salvos"),
    "savingFile": MessageLookupByLibrary.simpleMessage("Salvando arquivo..."),
    "selectColor": MessageLookupByLibrary.simpleMessage("Selecionar cor"),
    "selectNotImplemented": MessageLookupByLibrary.simpleMessage(
      "Selecionar (não implementado)",
    ),
    "setDocumentTitle": MessageLookupByLibrary.simpleMessage(
      "Definir título do documento.",
    ),
    "shapeCircle": MessageLookupByLibrary.simpleMessage("Círculo"),
    "shapeEllipse": MessageLookupByLibrary.simpleMessage("Elipse"),
    "shapeLine": MessageLookupByLibrary.simpleMessage("Linha"),
    "shapeOutlineColor": MessageLookupByLibrary.simpleMessage(
      "Cor do contorno",
    ),
    "shapeRectangle": MessageLookupByLibrary.simpleMessage("Retângulo"),
    "shapeSquare": MessageLookupByLibrary.simpleMessage("Quadrado"),
    "shapes": MessageLookupByLibrary.simpleMessage("Formas"),
    "sharePage": MessageLookupByLibrary.simpleMessage("Compartilhar página..."),
    "simplifyStrokes": MessageLookupByLibrary.simpleMessage(
      "Simplificar traços",
    ),
    "simplifyStrokesDescription": MessageLookupByLibrary.simpleMessage(
      "Reduzir pontos em novos traços para poupar espaço.",
    ),
    "sourceCode": MessageLookupByLibrary.simpleMessage("Código Fonte"),
    "storageBackend": MessageLookupByLibrary.simpleMessage(
      "Local de armazenamento",
    ),
    "strokeWidth": MessageLookupByLibrary.simpleMessage("Grossura da linha:"),
    "stylusPressureSensitivity": MessageLookupByLibrary.simpleMessage(
      "Sensibilidade à pressão da caneta",
    ),
    "stylusPressureSensitivityDescription":
        MessageLookupByLibrary.simpleMessage(
          "Ajustar a largura dos novos traços à pressão da caneta, quando disponível.",
        ),
    "successfullySaved": MessageLookupByLibrary.simpleMessage(
      "Salvo com sucesso",
    ),
    "successfullyShared": MessageLookupByLibrary.simpleMessage(
      "Compartilhado com sucesso",
    ),
    "textNotImplemented": MessageLookupByLibrary.simpleMessage(
      "Texto (não implementado)",
    ),
    "theFollowingErrorWasDetected": MessageLookupByLibrary.simpleMessage(
      "O seguinte erro foi detectado:",
    ),
    "thereWereNoMorePagesWeAddedOne": MessageLookupByLibrary.simpleMessage(
      "Não haviam mais páginas. Adicionamos uma.",
    ),
    "tool": MessageLookupByLibrary.simpleMessage("Ferramenta"),
    "toolboxNotImplementedYet": MessageLookupByLibrary.simpleMessage(
      "Caixa de ferramentas ainda não implementada.",
    ),
    "tools": MessageLookupByLibrary.simpleMessage("Ferramentas"),
    "unfortunatelyThereWasAnErrorSavingThisFile":
        MessageLookupByLibrary.simpleMessage(
          "Infelizmente houve um erro ao salvar este arquivo.",
        ),
    "used": MessageLookupByLibrary.simpleMessage("utilizado"),
    "workspaceCreate": MessageLookupByLibrary.simpleMessage("Criar caderno"),
    "workspaceEmptyDescription": MessageLookupByLibrary.simpleMessage(
      "Crie seu primeiro caderno ou abra um documento existente para começar.",
    ),
    "workspaceEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "Seu espaço de trabalho está pronto",
    ),
    "workspaceModified": m1,
    "workspaceOpen": MessageLookupByLibrary.simpleMessage("Abrir documento"),
    "workspaceRecents": MessageLookupByLibrary.simpleMessage(
      "Cadernos e documentos recentes",
    ),
    "workspaceSubtitle": MessageLookupByLibrary.simpleMessage(
      "Seus cadernos e documentos em um só lugar.",
    ),
    "workspaceTitle": MessageLookupByLibrary.simpleMessage(
      "Seu espaço de trabalho",
    ),
    "xournalMobileEditionIsAnUnofficialProjectTryingToMake":
        MessageLookupByLibrary.simpleMessage(
          "Xournal++ Mobile é um projeto que visa tornar as funcionalidades de Xournal++ e seus arquivos disponíveis em diferentes aparelhos.",
        ),
    "youDidNotSelectAnyFile": MessageLookupByLibrary.simpleMessage(
      "Você não selecionou nenhum arquivo.",
    ),
    "youveBeenRedirectedToTheLocalApp": MessageLookupByLibrary.simpleMessage(
      "Você foi redirecionado ao aplicativo local.",
    ),
  };
}
