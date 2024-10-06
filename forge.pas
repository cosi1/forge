{$I-}
program forge;
uses strings, sysutils;

const FORGE_VERSION = '0.0.1';

const
    numtokens : longint = 0; { number of tokens in the source code }
    codelength : word = 1; { code length (reserve 1 byte for RETURN) }
    varstack : word = 2; { variable table length }
    pc : word = 0; { program counter }
    lz : boolean = true; { false = compile for CM/XP }
    varblock : string = #0 + #0 + #0 + #0 + #0 + #0 + #0 + #0 + #0;
    pass : byte = 1;

var infilename, outfilename, flags : string;
    infile, outfile : text;
    tokens : array of pchar;
    i : byte;


{*** procedures and functions ***}

procedure readtokens;
const buf : string = '';
var ch : char;
begin
    while not eof(infile) do begin
        read(infile, ch);
        if ch in [#32, #9, #13, #10] then begin
            if length(buf) > 0 then begin
                if buf = '\' then begin
                    readln(infile, buf);
                end else begin
                    inc(numtokens);
                    setlength(tokens, numtokens);
                    getmem(tokens[numtokens - 1], length(buf) + 1);
                    strpcopy(tokens[numtokens - 1], buf);
                end;
                buf := '';
            end;
        end else begin
            buf := buf + ch;
        end;
    end;
    close(infile);
end;

procedure writeword(w : word);
begin
    write(outfile, chr(hi(w)), chr(lo(w)));
end;

procedure writecode(code : string);
begin
    if pass = 1 then
        inc(pc, length(code))
    else
        write(outfile, code);
end;

procedure writeheader;
var blocklength, varlength : word;
begin
    varlength := length(varblock); { length of the variable section }
    inc(codelength, pc);
    blocklength := varlength + codelength + 4; { 4 = size of varstack + codelength }
    write(outfile, 'ORG');
    writeword(blocklength + 4);
    write(outfile, #$83);
    writeword(blocklength);
    writeword(varstack);
    writeword(codelength);
end;

procedure writevars;
begin
    write(outfile, varblock);
end;

function parsevalue(v : string) : boolean;
var number, err : word;
begin
    val(v, number, err);
    if err = 0 then writecode(#$22 + chr(hi(number)) + chr(lo(number)));
    parsevalue := err = 0;
end;

function appendtostring(s, s0 : string) : string;
begin
    if s = '' then
        appendtostring := s0
    else
        appendtostring := s + ' ' + s0;
end;

procedure statusmsg(error : byte; errorinfo : string);
begin
    case error of
        0 : writeln('Translation complete');
        1 : writeln('Unrecognized identifier: ', errorinfo);
        else writeln('Error ', error);
    end;
    if error > 0 then halt(error);
end;

procedure translate;
const
    error : byte = 0;
    errorinfo : string = '';
    parsingstring : boolean = false;
    parsingcomment : boolean = false;
    parsedstring : string = '';
var token : string;
    stringcmd : string;
begin
    if lz then writecode(#$59 + #$b2);
    for i := low(tokens) to high(tokens) do begin
        token := tokens[i];
        if parsingcomment then begin
            if pos(')', token) = length(token) then begin
                parsingcomment := false;
            end;
        end else if parsingstring then begin
            if pos('"', token) = length(token) then begin
                delete(token, length(token), 1); { remove " }
                parsingstring := false;
                parsedstring := appendtostring(parsedstring, token);
                writecode(#$24 + chr(length(parsedstring)) + parsedstring);
                writecode(stringcmd);
            end else begin
                parsedstring := appendtostring(parsedstring, token);
            end;
        end else begin
            token := uppercase(token);
            case string(token) of
                '(' : parsingcomment := true;
                '."' : begin
                    stringcmd := #$71;
                    parsingstring := true;
                    parsedstring := '';
                end;
                'S"' : begin
                    stringcmd := '';
                    parsingstring := true;
                    parsedstring := '';
                end;
                '.' : writecode(#$6f);
                '<' : writecode(#$27);
                '<=' : writecode(#$28);
                '>' : writecode(#$29);
                '>=' : writecode(#$2a);
                '<>' : writecode(#$2b);
                '=' : writecode(#$2c);
                '+' : writecode(#$2d);
                '-' : writecode(#$2e);
                '*' : writecode(#$2f);
                '/' : writecode(#$30);
                '**' : writecode(#$31);
                'AND' : writecode(#$34);
                'ASC' : writecode(#$8b);
                'CLS' : writecode(#$4e);
                'CR' : writecode(#$73);
                'DAY' : writecode(#$8c);
                'DUP' : writecode(
                    #$22+#00+#$a5+ { push $a5 }
                    #$9c+#$9c); { peekw, peekw }
                'EMIT' : writecode(#$b8+#$71);
                'ERR' : writecode(#$8e);
                'DROP' : writecode(#$83);
                'GET' : writecode(#$91);
                'HEX$' : writecode(#$be);
                'NEG' : writecode(#$32); { unary - }
                'NOT' : writecode(#$33);
                'OR' : writecode(#$35);
                'PEEKB' : writecode(#$9b);
                'PEEKW' : writecode(#$9c);
                'POKEB' : writecode(#$55);
                'POKEW' : writecode(#$56);
                'PRINT' : writecode(#$71); { print string }
                'PRINT,' : writecode(#$72);
                'STOP' : writecode(#$59);
                'SWAP' : writecode(
                    #$89+#$de+#$a5+ { asm: ldx $a5 }
                    #$ec+#$00+#$dd+#$4b+ { ldd #0,X, std $4b }
                    #$ec+#$02+#$ed+#$00+ { ldd #2,X, std #0,X }
                    #$dc+#$4b+#$ed+#$02+ { ldd $4b, std #2,X }
                    #$dc+#$a9+#$c3+#$00+#$16+#$dd+#$a9+#$39); { rta_pc += $18 }
                'USR' : writecode(#$9f);
                else begin
                    if not parsevalue(token) then begin
                        error := 1;
                        errorinfo := token;
                        break;
                    end;
                end;
            end;
        end;
    end;
    { free memory }
    if (pass = 2) or (error > 0) then begin
        for i := low(tokens) to high(tokens) do begin
            freemem(tokens[i]);
        end;
        statusmsg(error, errorinfo);
    end;
end;

procedure finish;
begin
    write(outfile, #$7b, #00, #00);
    close(outfile);
end;


{*** main ***}

begin
    writeln('Forge version ', FORGE_VERSION);
    infilename := paramstr(1);
    outfilename := paramstr(2);
    flags := paramstr(3);
    if infilename = '' then begin
        writeln('Usage:');
        writeln('    forge input_file [output_file] [x]');
        halt(1);
    end;
    if outfilename = '' then begin
        i := pos('.', infilename);
        if i > 0 then
            outfilename := copy(infilename, 1, i - 1)
        else
            outfilename := infilename;
        outfilename := concat(outfilename, '.ob3');
    end;
    if pos('x', flags) > 0 then lz := false;
    assign(infile, infilename);
    reset(infile);
    i := ioresult;
    if i in [2, 3, 15] then begin
        writeln('File not found: ', infilename);
        halt(i);
    end else if i > 0 then begin
        writeln('Error opening ', infilename);
        halt(i)
    end;
    assign(outfile, outfilename);
    rewrite(outfile);
    i := ioresult;
    if i > 0 then begin
        writeln('Can''t open file for writing: ', outfilename);
        close(infile);
        halt(i);
    end;
    readtokens;
    translate;
    pass := 2;
    writeheader;
    writevars;
    translate;
    finish;
end.

