object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Atropos VCL'
  ClientHeight = 400
  ClientWidth = 600
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poScreenCenter
  DesignSize = (
    600
    400)
  TextHeight = 13
  object LblProject: TLabel
    Left = 16
    Top = 16
    Width = 111
    Height = 13
    Caption = 'Projeto Delphi (.dproj):'
  end
  object EdtProject: TEdit
    Left = 16
    Top = 35
    Width = 490
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    TabOrder = 0
  end
  object BtnBrowse: TButton
    Left = 512
    Top = 33
    Width = 75
    Height = 25
    Anchors = [akTop, akRight]
    Caption = 'Procurar...'
    TabOrder = 1
    OnClick = BtnBrowseClick
  end
  object GroupBoxOptions: TGroupBox
    Left = 16
    Top = 64
    Width = 571
    Height = 45
    Anchors = [akLeft, akTop, akRight]
    Caption = ' Op'#231#245'es de Limpeza e Ajuste '
    TabOrder = 2
    object ChkRemove: TCheckBox
      Left = 16
      Top = 18
      Width = 100
      Height = 17
      Caption = 'Remove Unused'
      TabOrder = 0
    end
    object ChkMove: TCheckBox
      Left = 122
      Top = 18
      Width = 140
      Height = 17
      Caption = 'Move to Implementation'
      TabOrder = 1
    end
    object ChkFormat: TCheckBox
      Left = 268
      Top = 18
      Width = 80
      Height = 17
      Caption = 'Format'
      TabOrder = 2
    end
    object ChkSort: TCheckBox
      Left = 354
      Top = 18
      Width = 80
      Height = 17
      Caption = 'Sort'
      TabOrder = 3
    end
    object ChkDebug: TCheckBox
      Left = 440
      Top = 18
      Width = 120
      Height = 17
      Caption = 'Enable Debug Logging'
      TabOrder = 4
    end
  end
  object BtnRun: TButton
    Left = 16
    Top = 120
    Width = 120
    Height = 33
    Caption = 'Iniciar Limpeza'
    TabOrder = 3
    OnClick = BtnRunClick
  end
  object ProgressBar1: TProgressBar
    Left = 144
    Top = 126
    Width = 443
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    TabOrder = 5
  end
  object MemoLog: TMemo
    Left = 16
    Top = 160
    Width = 571
    Height = 225
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 4
  end
  object OpenDialog1: TOpenDialog
    Filter = 'Projetos Delphi (*.dproj)|*.dproj'
    Left = 464
    Top = 8
  end
end
