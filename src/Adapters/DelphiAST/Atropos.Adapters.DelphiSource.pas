unit Atropos.Adapters.DelphiSource;

interface

uses System.RegularExpressions;

type
  TDelphiSourceContent = record
    Text: string;
    ContentHash: string;
  end;

  TDelphiSourceReader = class
  private
    class function CreateStringPlaceholder(const AMatch: TMatch): string; static;
    class function Normalize(const ASource: string): string; static;
  public
    class function Read(const AFilePath: string): TDelphiSourceContent; static;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash;

class function TDelphiSourceReader.CreateStringPlaceholder(
  const AMatch: TMatch): string;
var
  LLineBreaks: string;
begin
  LLineBreaks := TRegEx.Replace(AMatch.Value, '[^\r\n]', EmptyStr);
  Result := '''''' + LLineBreaks;
end;

class function TDelphiSourceReader.Normalize(const ASource: string): string;
const
  CMultilineStringPattern = '^[\t ]*''''''[\t ]*\r?\n.*?^[\t ]*''''''';
var
  LIndex: Integer;
  LMatch: TMatch;
  LMatches: TMatchCollection;
  LPlaceholder: string;
begin
  Result := ASource;
  LMatches := TRegEx.Matches(ASource, CMultilineStringPattern,
    [roMultiLine, roSingleLine]);
  for LIndex := LMatches.Count - 1 downto 0 do
  begin
    LMatch := LMatches.Item[LIndex];
    LPlaceholder := CreateStringPlaceholder(LMatch);
    Delete(Result, LMatch.Index, LMatch.Length);
    Insert(LPlaceholder, Result, LMatch.Index);
  end;
end;

class function TDelphiSourceReader.Read(
  const AFilePath: string): TDelphiSourceContent;
var
  LBytes: TBytes;
  LEncoding: TEncoding;
  LPreambleSize: Integer;
  LHash: THashSHA2;
begin
  LBytes := TFile.ReadAllBytes(AFilePath);
  LEncoding := nil;
  LPreambleSize := TEncoding.GetBufferEncoding(LBytes, LEncoding, TEncoding.UTF8);
  Result.Text := Normalize(LEncoding.GetString(LBytes, LPreambleSize,
    Length(LBytes) - LPreambleSize));
  LHash := THashSHA2.Create;
  LHash.Update(LBytes);
  Result.ContentHash := LHash.HashAsString;
end;

end.
