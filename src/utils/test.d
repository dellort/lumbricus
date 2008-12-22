module utils.test;

//for reflection.d
//must test, if all members are accessible from tuples
//the calling code and the class must be in different modules
class Test {
    int a;
    protected int b;
    private int c;
    package int d;

    struct S {
    }
}
