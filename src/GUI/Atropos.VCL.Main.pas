unit Atropos.VCL.Main;

interface

uses
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Winapi.Messages,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.UITypes,
  Vcl.Controls,
  Atropos.Application.AppService,
  Atropos.Application.ExecutionConfig,
  Atropos.Application.ExecutionPresentation,
  Atropos.Application.Factory,
  Atropos.Core.Config;

type
  TMainForm = class(TForm)
    ProjectLabel: TLabel;
    ProjectEdit: TEdit;
    BrowseButton: TButton;
    RunButton: TButton;
    CancelButton: TButton;
    ExecutionProgressBar: TProgressBar;
    LogMemo: TMemo;
    ProjectOpenDialog: TOpenDialog;
    OptionsGroupBox: TGroupBox;
    RemoveCheckBox: TCheckBox;
    MoveCheckBox: TCheckBox;
    DebugCheckBox: TCheckBox;
    procedure BrowseButtonClick(Sender: TObject);
    procedure RunButtonClick(Sender: TObject);
    procedure CancelButtonClick(Sender: TObject);
  private
    FExecutionPresentation: TExecutionPresentation;
    procedure ApplyExecutionState;
    procedure LogMessage(const AMsg: string);
    procedure UpdateProgress(AMax, APosition: Integer);
    procedure ExecuteProcess(const ADprojPath: string; const AConfig: TToolConfig);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function CloseQuery: Boolean; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited;
  FExecutionPresentation := TExecutionPresentation.Create;
  ApplyExecutionState;
end;

destructor TMainForm.Destroy;
begin
  FExecutionPresentation.Free;
  inherited;
end;

function TMainForm.CloseQuery: Boolean;
begin
  Result := FExecutionPresentation.CanClose;
  if not Result then
    MessageDlg('A análise ainda está em execução. Aguarde a conclusão antes de fechar o Atropos.',
      mtWarning, [mbOK], 0);
end;

procedure TMainForm.ApplyExecutionState;
begin
  RunButton.Enabled := FExecutionPresentation.State.ControlsEnabled;
  BrowseButton.Enabled := FExecutionPresentation.State.ControlsEnabled;
  CancelButton.Enabled := FExecutionPresentation.State.CancelEnabled;
  ExecutionProgressBar.Max := FExecutionPresentation.State.ProgressMaximum;
  ExecutionProgressBar.Position := FExecutionPresentation.State.ProgressPosition;
end;

procedure TMainForm.BrowseButtonClick(Sender: TObject);
begin
  if ProjectOpenDialog.Execute then
    ProjectEdit.Text := ProjectOpenDialog.FileName;
end;

procedure TMainForm.LogMessage(const AMsg: string);
begin
  TThread.Queue(TThread.CurrentThread,
    procedure
    begin
      LogMemo.Lines.Add(AMsg);
      SendMessage(LogMemo.Handle, EM_LINESCROLL, 0, LogMemo.Lines.Count);
    end);
end;

procedure TMainForm.UpdateProgress(AMax, APosition: Integer);
begin
  TThread.Queue(TThread.CurrentThread,
    procedure
    begin
      FExecutionPresentation.UpdateProgress(AMax, APosition);
      ApplyExecutionState;
    end);
end;

procedure TMainForm.ExecuteProcess(const ADprojPath: string; const AConfig: TToolConfig);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LAppService: TProjectCleanerAppService;
    begin
      try
        LAppService := TAppServiceFactory.CreateDefault(AConfig,
          function: Boolean
          begin
            Result := FExecutionPresentation.IsCancellationRequested;
          end);
        try
          LAppService.OnLog := procedure(const AMsg: string)
            begin
              LogMessage(AMsg);
            end;
          
          LAppService.OnProgress := procedure(AMax, APosition: Integer)
            begin
              UpdateProgress(AMax, APosition);
            end;
          
          LAppService.Execute(ADprojPath);
        finally
          LAppService.Free;
        end;
      except
        on E: Exception do
          LogMessage('Critical Error: ' + E.Message);
      end;
      TThread.Queue(TThread.CurrentThread,
        procedure
        begin
          FExecutionPresentation.Complete;
          ApplyExecutionState;
        end);
    end).Start;
end;

procedure TMainForm.CancelButtonClick(Sender: TObject);
begin
  FExecutionPresentation.RequestCancellation;
  ApplyExecutionState;
  LogMemo.Lines.Add('Cancellation requested. Waiting for the current operation to stop...');
end;

procedure TMainForm.RunButtonClick(Sender: TObject);
var
  LConfig: TToolConfig;
begin
  if not FExecutionPresentation.TryBegin then
    Exit;

  if not FileExists(ProjectEdit.Text) then
  begin
    FExecutionPresentation.Complete;
    ApplyExecutionState;
    ShowMessage('Selecione um projeto válido!');
    Exit;
  end;
  
  LogMemo.Clear;
  ApplyExecutionState;
  
  LConfig := TExecutionConfigFactory.FromSelections(
    RemoveCheckBox.Checked,
    MoveCheckBox.Checked,
    DebugCheckBox.Checked);
  ExecuteProcess(ProjectEdit.Text, LConfig);
end;

end.
