def _get_stackentry(code_filename, code, filename, linenumber, funcname)
    nlinenumber = linenumber.to_i
    stackentry = {"file" => filename, "linenumber" => nlinenumber, "duplicates" => 1}

    if filename == "(eval)" or filename == code_filename
        codelines = code.split("\n")
        if (nlinenumber >= 1) && (nlinenumber <= codelines.size)
            stackentry["linetext"] = codelines[nlinenumber-1]
        elsif (nlinenumber == codelines.size + 1)
            stackentry["linetext"] = "<end of file>"
        else
            stackentry["linetext"] = "getExceptionTraceback: ScraperWiki internal error, line %d out of range in file %s" % [nlinenumber, code_filename]
        end
        stackentry["file"] = "<string>"
    else
        # XXX bit of a hack to show the line number in third party libraries
        stackentry["file"] += ":" + linenumber
    end
    if funcname
        stackentry["furtherlinetext"] = funcname
    end
    return stackentry
end

def getExceptionTraceback(e, code, code_filename)
    lbacktrace = e.backtrace.reverse
    #File.open("/tmp/fairuby", 'a') {|f| f.write(JSON.generate(lbacktrace)) }

    exceptiondescription = e.inspect
    
    stackdump = []
    for l in lbacktrace
        (filename, linenumber, funcname) = l.split(":")

        next if filename.match(/\/exec.rb$/) # skip showing stack of wrapper

        stackentry = _get_stackentry(code_filename, code, filename, linenumber, funcname)
        stackdump.push(stackentry)
    end

    if e.kind_of?(SyntaxError)
        (filename, linenumber, message) = exceptiondescription.split(/[:\n]/, 3)
        exceptiondescription = message

        stackentry = _get_stackentry(code_filename, code, filename, linenumber, nil)
        stackdump.push(stackentry)
    end

    return { 'message_type' => 'exception', 'exceptiondescription' => exceptiondescription, "stackdump" => stackdump }
end
