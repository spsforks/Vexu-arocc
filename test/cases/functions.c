int foo(int bar) {
    (void)sizeof(struct Foo { int a; });
    (void)__alignof(struct Foo);
    return bar;
}

int fooo(bar, baz)
    float bar;
    int *baz;
    double quux;
{
    return *baz * bar;
}

#define EXPECTED_ERRORS "functions.c:10:12: error: parameter named 'quux' is missing"
