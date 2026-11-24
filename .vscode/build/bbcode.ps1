# Converts the Markdown the mod READMEs and changelogs use into Steam's BBCode: headings, paragraphs, bold,
# italic, strikethrough, inline code, links, nested lists, blockquotes, tables, horizontal rules and code blocks.

$BBCodePlaceholder = [char]0xE000

function ConvertTo-BBCodeInline {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$LinkBase
    )

    $codeSpans = [System.Collections.Generic.List[string]]::new()
    $result = [regex]::Replace($Text, '`([^`]+)`', {
            param($match)
            $codeSpans.Add($match.Groups[1].Value)
            "$BBCodePlaceholder$($codeSpans.Count - 1)$BBCodePlaceholder"
        })
    $result = [regex]::Replace($result, '\[([^\]]+)\]\(([^)\s]+)\)', {
            param($match)
            "[url=$(Resolve-LinkTarget -Target $match.Groups[2].Value -LinkBase $LinkBase)]$($match.Groups[1].Value)[/url]"
        })
    $result = [regex]::Replace($result, '\*\*(.+?)\*\*', '[b]$1[/b]')
    $result = [regex]::Replace($result, '(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])', '[i]$1[/i]')
    $result = [regex]::Replace($result, '~~(.+?)~~', '[strike]$1[/strike]')
    $result = [regex]::Replace($result, '<br\s*/?>', "`n")
    [regex]::Replace($result, "$BBCodePlaceholder(\d+)$BBCodePlaceholder", {
            param($match)
            "[b]$($codeSpans[[int]$match.Groups[1].Value])[/b]"
        })
}

function Resolve-LinkTarget {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$LinkBase
    )

    if ($Target -match '^[a-z][a-z0-9+.-]*:') { return $Target }
    if ($Target.StartsWith('#')) { return "${LinkBase}README.md$Target" }
    [System.Uri]::new([System.Uri]$LinkBase, $Target).AbsoluteUri
}

function Test-BlockStart {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)

    $Line -match '^\s*(#{1,6}\s|>|\||```|([-*+]|\d+\.)\s|(-{3,}|\*{3,})\s*$)'
}

function Split-TableRow {
    param([Parameter(Mandatory)][string]$Line)

    @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
}

function ConvertFrom-MarkdownTable {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$LinkBase
    )

    $rows = [System.Collections.Generic.List[string]]::new()
    $headerCells = Split-TableRow -Line $Lines[0] | ForEach-Object { "[th]$(ConvertTo-BBCodeInline -Text $_ -LinkBase $LinkBase)[/th]" }
    $rows.Add("[tr]$($headerCells -join '')[/tr]")
    foreach ($row in $Lines | Select-Object -Skip 2) {
        $cells = Split-TableRow -Line $row | ForEach-Object { "[td]$(ConvertTo-BBCodeInline -Text $_ -LinkBase $LinkBase)[/td]" }
        $rows.Add("[tr]$($cells -join '')[/tr]")
    }
    "[table]`n$($rows -join "`n")`n[/table]"
}

function ConvertFrom-MarkdownList {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$LinkBase
    )

    $entries = foreach ($line in $Lines) {
        if ($line -match '^(\s*)(?:([-*+])|\d+\.)\s+(.*)$') {
            [pscustomobject]@{ Indent = $Matches[1].Length; Ordered = -not $Matches[2]; Text = $Matches[3] }
        }
        else {
            [pscustomobject]@{ Indent = -1; Ordered = $false; Text = $line.Trim() }
        }
    }
    (ConvertFrom-ListEntries -Entries @($entries) -LinkBase $LinkBase).Text
}

function ConvertFrom-ListEntries {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$LinkBase,
        [int]$Start = 0
    )

    $indent = $Entries[$Start].Indent
    $tag = if ($Entries[$Start].Ordered) { 'olist' } else { 'list' }
    $items = [System.Collections.Generic.List[string]]::new()
    $index = $Start
    while ($index -lt $Entries.Count) {
        $entry = $Entries[$index]
        if ($entry.Indent -ge 0 -and $entry.Indent -lt $indent) { break }
        if ($entry.Indent -gt $indent) {
            $nested = ConvertFrom-ListEntries -Entries $Entries -LinkBase $LinkBase -Start $index
            $items[$items.Count - 1] += "`n$($nested.Text)"
            $index = $nested.Next
            continue
        }
        if ($entry.Indent -lt 0) {
            $items[$items.Count - 1] += " $(ConvertTo-BBCodeInline -Text $entry.Text -LinkBase $LinkBase)"
        }
        else {
            $items.Add("[*]$(ConvertTo-BBCodeInline -Text $entry.Text -LinkBase $LinkBase)")
        }
        $index++
    }
    [pscustomobject]@{ Text = "[$tag]`n$($items -join "`n")`n[/$tag]"; Next = $index }
}

function ConvertTo-SteamBBCode {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$LinkBase
    )

    $blocks = [System.Collections.Generic.List[string]]::new()
    $index = 0
    while ($index -lt $Lines.Count) {
        $line = $Lines[$index]
        if ($line -match '^\s*$') {
            $index++
        }
        elseif ($line -match '^\s*```') {
            $code = [System.Collections.Generic.List[string]]::new()
            $index++
            while ($index -lt $Lines.Count -and $Lines[$index] -notmatch '^\s*```') {
                $code.Add($Lines[$index])
                $index++
            }
            $index++
            $blocks.Add("[code]$($code -join "`n")[/code]")
        }
        elseif ($line -match '^(#{1,6})\s+(.+?)\s*$') {
            $level = [Math]::Min($Matches[1].Length, 3)
            $title = ConvertTo-BBCodeInline -Text $Matches[2] -LinkBase $LinkBase
            $index++
            $blocks.Add("[h$level]$title[/h$level]")
        }
        elseif ($line -match '^\s*(-{3,}|\*{3,})\s*$') {
            $blocks.Add('[hr][/hr]')
            $index++
        }
        elseif ($line -match '^\s*>') {
            $quote = [System.Collections.Generic.List[string]]::new()
            while ($index -lt $Lines.Count -and $Lines[$index] -match '^\s*>') {
                $quote.Add(($Lines[$index] -replace '^\s*> ?', ''))
                $index++
            }
            $inner = ConvertTo-SteamBBCode -Lines $quote.ToArray() -LinkBase $LinkBase
            $blocks.Add("[quote]$inner[/quote]")
        }
        elseif ($line -match '^\s*\|' -and $index + 1 -lt $Lines.Count -and $Lines[$index + 1] -match '^\s*\|?\s*:?-{3,}') {
            $table = [System.Collections.Generic.List[string]]::new()
            while ($index -lt $Lines.Count -and $Lines[$index] -match '^\s*\|') {
                $table.Add($Lines[$index])
                $index++
            }
            $blocks.Add((ConvertFrom-MarkdownTable -Lines $table.ToArray() -LinkBase $LinkBase))
        }
        elseif ($line -match '^\s*([-*+]|\d+\.)\s') {
            $list = [System.Collections.Generic.List[string]]::new()
            while ($index -lt $Lines.Count -and ($Lines[$index] -match '^\s*([-*+]|\d+\.)\s' -or ($Lines[$index] -match '^\s+\S' -and $list.Count -gt 0))) {
                $list.Add($Lines[$index])
                $index++
            }
            $blocks.Add((ConvertFrom-MarkdownList -Lines $list.ToArray() -LinkBase $LinkBase))
        }
        else {
            $paragraph = [System.Collections.Generic.List[string]]::new()
            while ($index -lt $Lines.Count -and $Lines[$index] -notmatch '^\s*$' -and -not ($paragraph.Count -gt 0 -and (Test-BlockStart -Line $Lines[$index]))) {
                $paragraph.Add($Lines[$index].Trim())
                $index++
            }
            $blocks.Add((ConvertTo-BBCodeInline -Text ($paragraph -join ' ') -LinkBase $LinkBase))
        }
    }
    $blocks -join "`n`n"
}

function Read-MarkdownLine {
    param([Parameter(Mandatory)][string]$Path)

    (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).TrimStart([char]0xFEFF) -split '\r?\n'
}
